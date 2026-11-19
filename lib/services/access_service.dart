import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'remote_config.dart';

/// The single source of truth for whether this app instance may be used.
///
/// Every user lives in `users/{userId}` in Firestore with:
///   businessName      -> shown in the app header and on bills
///   phone             -> login mobile number
///   pinHash/pinSalt   -> salted SHA-256 of the 4-digit Quick PIN
///                        (NEVER the plain PIN)
///   status            -> "pending" | "active" | "blocked"
///   expiryDate        -> Firestore Timestamp; null = no expiry
///   maxDevices        -> default 2
///   registeredDevices -> list of unique device IDs allowed to run
///
/// The service evaluates status + expiry + device on:
///   * every app launch (cached snapshot keeps working offline)
///   * a LIVE Firestore listener (kill-switch: the admin can flip
///     "status" to "blocked" and the app locks itself instantly,
///     even while it is open)
///   * after every background sync tick
class AccessService {
  AccessService._();
  static final AccessService instance = AccessService._();

  static const _kDeviceId = 'device_id';
  static const _kAccountCache = 'account_cache_v1';

  final ValueNotifier<AccessState> state =
      ValueNotifier<AccessState>(AccessState.checking);
  final ValueNotifier<AccountInfo?> account = ValueNotifier<AccountInfo?>(null);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _deviceId;

  bool get fbReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Unique, stable ID of THIS physical device.
  /// Android: Settings.Secure ANDROID_ID. Elsewhere / failure: a random
  /// UUID persisted once in SharedPreferences.
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final sp = await SharedPreferences.getInstance();
    var id = sp.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      try {
        final plugin = DeviceInfoPlugin();
        if (defaultTargetPlatform == TargetPlatform.android) {
          final android = await plugin.androidInfo;
          id = android.id; // ANDROID_ID - stable per app signing key
        }
      } catch (_) {
        // plugin not available (tests / desktop) - fall through
      }
      id ??= const Uuid().v4();
      await sp.setString(_kDeviceId, id);
    }
    _deviceId = id;
    return id;
  }

  // ------------------------------------------------------------------
  // Registration side: create / repair the users/{uid} document.
  // ------------------------------------------------------------------

  /// Creates the user document at registration. While the remote
  /// `auto_approve` flag is ON (the default - see docs/REMOTE_CONTROL.md)
  /// the account is born "active" so the owner walks straight in; the
  /// Admin can still kill-switch it later. With the flag OFF it is born
  /// "pending" and waits for manual admin approval.
  /// If a doc already exists (2nd device / reinstall) the MASTER COPY in
  /// Firestore wins and the local PIN is imported from it, so the same
  /// mobile number works on both devices with the same Quick PIN.
  Future<AccountInfo> registerUser({
    required String phone,
    required String businessName,
    required String pinHash,
    required String pinSalt,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final devId = await deviceId();
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);

    final snap = await doc.get();
    if (snap.exists) {
      // Existing master account - import it (this is a 2nd device).
      final info = AccountInfo.fromMap(uid, snap.data()!);
      if (info.status == 'pending') await selfActivateIfAllowed();
      await _registerDeviceIfNeeded(info);
      return info;
    }

    final auto = RemoteConfigService.instance.config.value.autoApprove;
    final now = DateTime.now();
    // Default subscription: 365 days, admin can change it any time.
    final info = AccountInfo(
      uid: uid,
      businessName: businessName.trim(),
      phone: phone,
      status: auto ? 'active' : 'pending',
      expiryDate: now.add(const Duration(days: 365)),
      maxDevices: 2,
      registeredDevices: [devId],
      pinHash: pinHash,
      pinSalt: pinSalt,
    );
    await doc.set(info.toMap()..['createdAt'] = now.millisecondsSinceEpoch);
    await _cacheAccount(info);
    return info;
  }

  /// One-shot self-activation: while the remote `auto_approve` flag is
  /// ON, an account stuck at "pending" (registered on an older app
  /// version, or before the flag was reviewed) promotes itself to
  /// "active". The Firestore rules allow exactly this transition and
  /// nothing else, so this stays harmless once the flag is turned off.
  /// Returns true when the document is (now) active.
  Future<bool> selfActivateIfAllowed() async {
    if (!fbReady) return false;
    if (!RemoteConfigService.instance.config.value.autoApprove) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await doc.get();
      if (!snap.exists) return false;
      if ((snap.data()?['status'] ?? '') != 'pending') return true;
      await doc.update({
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await verifyOnce(); // re-read + re-evaluate (also refreshes cache)
      return true;
    } catch (_) {
      // Offline / rules denied / flag off on the server - stay pending.
      return false;
    }
  }

  Future<void> _registerDeviceIfNeeded(AccountInfo info) async {
    final devId = await deviceId();
    if (info.registeredDevices.contains(devId)) return;
    if (info.registeredDevices.length >= info.maxDevices) return; // full
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'registeredDevices': FieldValue.arrayUnion([devId]),
    });
    info.registeredDevices = [...info.registeredDevices, devId];
  }

  // ------------------------------------------------------------------
  // Live watching (the kill-switch).
  // ------------------------------------------------------------------

  /// Starts listening to users/{uid}. Works offline too, because
  /// Firestore offline persistence serves the last known snapshot.
  void startWatching() {
    stopWatching();
    if (!fbReady) {
      state.value = AccessState.allowed; // pure offline mode: no admin gate
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state.value = AccessState.signedOut;
      return;
    }
    // Evaluate from the cached snapshot first, so an offline launch is
    // protected by the last known admin decision.
    _evaluateOffline();
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || snap.data() == null) {
        // No master record - treat as pending (admin must act).
        state.value = AccessState.pending;
        return;
      }
      final info = AccountInfo.fromMap(user.uid, snap.data()!);
      await _registerDeviceIfNeeded(info);
      await _cacheAccount(info);
      account.value = info;
      state.value = info.evaluateFor(await deviceId());
    }, onError: (e) {
      // Listener error (permissions/network): cached verdict first, then
      // the local registration fallback so an updated device never hangs
      // on the splash.
      if (state.value == AccessState.checking) {
        _evaluateOffline();
      }
    });
  }

  void stopWatching() {
    _sub?.cancel();
    _sub = null;
  }

  /// Called after every background sync tick (spec: verify on every sync).
  /// One-shot read of users/{uid} + evaluate - cheap, and it re-locks the
  /// app even if the snapshot listener somehow missed a change.
  Future<void> verifyOnce() async {
    if (!fbReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!snap.exists || snap.data() == null) {
        state.value = AccessState.pending;
        return;
      }
      final info = AccountInfo.fromMap(user.uid, snap.data()!);
      await _registerDeviceIfNeeded(info);
      await _cacheAccount(info);
      account.value = info;
      state.value = info.evaluateFor(await deviceId());
    } catch (_) {
      // Offline / permission error: cached verdict, then the local
      // registration fallback - a previously registered device keeps
      // working until connectivity returns and the server re-checks.
      if (state.value == AccessState.checking) {
        await _evaluateOffline();
      }
    }
  }

  void recheckNow() => verifyOnce();

  Future<void> _evaluateFromCache() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kAccountCache);
    if (raw == null || raw.isEmpty) return; // nothing cached yet
    try {
      final info = AccountInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      account.value = info;
      state.value = info.evaluateFor(await deviceId());
    } catch (_) {
      // corrupt cache - ignore, the live listener will decide
    }
  }

  /// Update / offline safety net: the cached admin verdict first; when
  /// nothing is cached yet, fall back to the local registration marks.
  /// A phone that was registered on THIS device earlier (the APK-update
  /// case) stays allowed instead of hanging on the splash - the very
  /// next listener event / verifyOnce() re-checks the server, and the
  /// admin kill-switch applies the moment connectivity returns.
  Future<void> _evaluateOffline() async {
    await _evaluateFromCache();
    if (state.value != AccessState.checking) return;
    final sp = await SharedPreferences.getInstance();
    final reg = sp.getString('reg_phone') ?? '';
    state.value = reg.isEmpty ? AccessState.pending : AccessState.allowed;
  }

  Future<void> _cacheAccount(AccountInfo info) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAccountCache, jsonEncode(info.toCache()));
  }

  /// Sign out / forget this device registration locally.
  Future<void> signOut() async {
    stopWatching();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    state.value = AccessState.signedOut;
    account.value = null;
  }
}

enum AccessState {
  checking, // booting up, deciding
  allowed, // active + not expired + approved device
  pending, // status == "pending" - waiting for admin approval
  blocked, // status == "blocked" - admin kill-switch
  expired, // DateTime.now() is after expiryDate
  deviceLimit, // device not in registeredDevices and 2 devices already used
  signedOut, // no Firebase session
}

/// Snapshot of the users/{uid} Firestore document.
class AccountInfo {
  final String uid;
  final String businessName;
  final String phone;
  final String status; // pending | active | blocked
  final DateTime? expiryDate; // null = no expiry
  final int maxDevices;
  List<String> registeredDevices;
  final String pinHash;
  final String pinSalt;

  AccountInfo({
    required this.uid,
    required this.businessName,
    required this.phone,
    required this.status,
    required this.expiryDate,
    required this.maxDevices,
    required this.registeredDevices,
    this.pinHash = '',
    this.pinSalt = '',
  });

  factory AccountInfo.fromMap(String uid, Map<String, dynamic> m) {
    DateTime? expiry;
    final raw = m['expiryDate'];
    if (raw is Timestamp) expiry = raw.toDate();
    if (raw is int) expiry = DateTime.fromMillisecondsSinceEpoch(raw);
    return AccountInfo(
      uid: uid,
      businessName: (m['businessName'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      status: (m['status'] ?? 'pending') as String,
      expiryDate: expiry,
      maxDevices: ((m['maxDevices'] ?? 2) as num).toInt(),
      registeredDevices: ((m['registeredDevices'] ?? const []) as List)
          .map((e) => e.toString())
          .toList(),
      pinHash: (m['pinHash'] ?? '') as String,
      pinSalt: (m['pinSalt'] ?? '') as String,
    );
  }

  /// The exact access rule from the spec, as a pure function:
  /// status == "active" AND now < expiryDate AND device approved.
  AccessState evaluateFor(String deviceId, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (status == 'blocked') return AccessState.blocked;
    if (status != 'active') return AccessState.pending;
    if (expiryDate != null && t.isAfter(expiryDate!)) {
      return AccessState.expired;
    }
    if (registeredDevices.contains(deviceId)) return AccessState.allowed;
    if (registeredDevices.length >= maxDevices) return AccessState.deviceLimit;
    return AccessState.allowed; // room left; device will auto-register
  }

  Map<String, dynamic> toMap() => {
        'businessName': businessName,
        'phone': phone,
        'status': status,
        'expiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate!),
        'maxDevices': maxDevices,
        'registeredDevices': registeredDevices,
        if (pinHash.isNotEmpty) 'pinHash': pinHash,
        if (pinSalt.isNotEmpty) 'pinSalt': pinSalt,
      };

  Map<String, dynamic> toCache() => {
        'uid': uid,
        'businessName': businessName,
        'phone': phone,
        'status': status,
        'expiryMs': expiryDate?.millisecondsSinceEpoch,
        'maxDevices': maxDevices,
        'registeredDevices': registeredDevices,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
      };

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        uid: (j['uid'] ?? '') as String,
        businessName: (j['businessName'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        expiryDate: j['expiryMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['expiryMs'] as num).toInt()),
        maxDevices: ((j['maxDevices'] ?? 2) as num).toInt(),
        registeredDevices: ((j['registeredDevices'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        pinHash: (j['pinHash'] ?? '') as String,
        pinSalt: (j['pinSalt'] ?? '') as String,
      );
}
