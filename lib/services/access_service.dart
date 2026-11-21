import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/repo.dart';
import 'remote_config.dart';

/// The single source of truth for whether this app instance may be used.
///
/// Every user lives in `users/{userId}` in Firestore with:
///   businessName      -> shown in the app header and on bills
///   ownerName/mobile/city/address/gst -> business registration details
///   email             -> Google login account (read-only)
///   pinHash/pinSalt   -> salted SHA-256 of the 4-digit Quick PIN
///                        (NEVER the plain PIN)
///   status            -> "pending" | "active" | "blocked"
///   plan              -> "free" | "paid" | "trial" (legacy) | '' (legacy)
///   trialStartDate/trialEndDate -> legacy trial window (READ-ONLY since
///                        v0.3.0 - the 7-day trial system was removed;
///                        these fields no longer affect access at all)
///   subscriptionEndDate -> set by the Admin / Ruby Key (or Razorpay later)
///   expiryDate        -> legacy field; still honoured for old accounts
///   maxDevices        -> default 2
///   registeredDevices -> list of unique device IDs allowed to run
///   deviceModels      -> {deviceId: model} so the owner recognises devices
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
  // BLOCKER 2 (v0.4.3): per-device NUMBER SLOT for offline bill /
  // purchase / return numbering. Slot 0 = legacy + single-device era
  // (plain 1,2,3...); slot = index in registeredDevices + 1 for a
  // multi-device shop (100,xxx / 200,xxx) - two devices can never share
  // a range, so two offline phones can never pick the same number.
  // The Firestore rules only allow the list to GROW or SHRINK (never a
  // wholesale swap), so positions are stable across devices.
  // ------------------------------------------------------------------

  /// Pure slot resolver (unit-tested). Unregistered / unknown device
  /// gets the fallback slot 9 (Repo.numberSlotFallback).
  static int numberSlotFor(String deviceId, List<String> registeredDevices) {
    if (registeredDevices.contains(deviceId)) {
      if (registeredDevices.length <= 1) return 0; // single-device shop:
      // plain numbering, exactly like the legacy era.
      return registeredDevices.indexOf(deviceId) + 1; // 1..N, unique per device
    }
    return Repo.numberSlotFallback;
  }

  /// Push the current slot into the local meta table. Called on every
  /// account refresh; a failure here must never affect the access
  /// verdict (numbering falls back to slot 9 + the duplicate healer).
  Future<void> _updateNumberSlot(AccountInfo info) async {
    try {
      final me = await deviceId();
      await Repo.instance.setNumberSlot(numberSlotFor(me, info.registeredDevices));
    } catch (_) {
      // Keep last known slot - never throw into the access path.
    }
  }

  // ------------------------------------------------------------------
  // Registration side: create / repair the users/{uid} document.
  // ------------------------------------------------------------------

  /// Creates the user document at registration. While the remote
  /// `auto_approve` flag is ON (the default - see docs/REMOTE_CONTROL.md)
  /// the account is born "active" so the owner walks straight in (no
  /// waiting screen); the Admin can still kill-switch it later. With the
  /// flag OFF it is born "pending" and waits for manual admin approval.
  /// Login is Google-based (Gmail), no SMS.
  ///
  /// v0.3.0: NO 7-day trial anymore - a new account is born usable and
  /// stays usable until the Admin (Ruby Key) blocks it or sets an end
  /// date (subscriptionEndDate / expiryDate). The old trial fields are
  /// kept only for reading legacy accounts; they no longer decide
  /// anything.
  /// If a doc already exists (2nd device / reinstall) the MASTER COPY in
  /// Firestore wins and the local PIN is imported from it, so the same
  /// account works on both devices with the same Quick PIN.
  Future<AccountInfo> registerUser({
    required String email,
    required String businessName,
    String ownerName = '',
    String mobile = '',
    String city = '',
    String address = '',
    String gst = '',
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
      await _updateNumberSlot(info);
      return info;
    }

    final auto = RemoteConfigService.instance.config.value.autoApprove;
    // v0.3.0: no 7-day trial - the account is usable immediately. Only
    // the Admin (Ruby Key) can block it or set an end date later.
    final info = AccountInfo(
      uid: uid,
      businessName: businessName.trim(),
      email: email,
      ownerName: ownerName.trim(),
      mobile: mobile.trim(),
      city: city.trim(),
      address: address.trim(),
      gst: gst.trim(),
      status: auto ? 'active' : 'pending',
      plan: 'free',
      trialStartDate: 0,
      trialEndDate: null,
      expiryDate: null,
      maxDevices: 2,
      registeredDevices: [devId],
      deviceModels: {devId: await deviceModel()},
      pinHash: pinHash,
      pinSalt: pinSalt,
    );
    await doc.set(info.toMap()
      ..['createdAt'] = DateTime.now().millisecondsSinceEpoch
      ..['updatedAt'] = FieldValue.serverTimestamp());
    await _cacheAccount(info);
    await _updateNumberSlot(info);
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
      'deviceModels.$devId': await deviceModel(),
    });
    info.registeredDevices = [...info.registeredDevices, devId];
    info.deviceModels[devId] = await deviceModel();
  }

  /// Removes one of this account's registered devices (self-serve, from
  /// the Device Limit screen). After removal there is room again, so the
  /// CURRENT device auto-registers on the next access check.
  Future<void> removeDevice(String devId) async {
    if (!fbReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'registeredDevices': FieldValue.arrayRemove([devId]),
        'deviceModels.$devId': FieldValue.delete(),
      });
    } catch (_) {
      // Offline / denied - the live listener will retry the verdict.
      return;
    }
    await verifyOnce();
  }

  /// Human-readable model of THIS device, e.g. "Redmi Note 12".
  Future<String> deviceModel() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await DeviceInfoPlugin().androidInfo;
        final brand = android.manufacturer.trim();
        final model = android.model.trim();
        if (model.isEmpty) return brand;
        if (brand.isEmpty || model.toLowerCase().startsWith(brand.toLowerCase())) {
          return model;
        }
        return '$brand $model';
      }
    } catch (_) {}
    return 'Unknown device';
  }

  /// Business Profile edits (Settings -> Business Profile). Only the
  /// profile fields move through this path - status / plan / validity /
  /// device list are admin-controlled and never touched here.
  Future<void> updateBusinessProfile({
    required String businessName,
    required String ownerName,
    required String mobile,
    required String city,
    required String address,
    required String gst,
  }) async {
    if (!fbReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'businessName': businessName.trim(),
      'ownerName': ownerName.trim(),
      'mobile': mobile.trim(),
      'city': city.trim(),
      'address': address.trim(),
      'gst': gst.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await verifyOnce();
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
      await _updateNumberSlot(info);
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
      await _updateNumberSlot(info);
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

  /// SPLASH FAILSAFE: resolve a "checking" verdict IMMEDIATELY from
  /// the cached admin snapshot and the local registration marks -
  /// never from the network. Called by the AuthGate 3-second failsafe
  /// timer when the live users/{uid} verdict has not arrived in time
  /// (slow network, Clear Data, Firestore hang). The normal live
  /// listener keeps running and corrects the verdict the moment the
  /// real snapshot lands.
  Future<void> resolveFromCacheNow() async {
    if (state.value != AccessState.checking) return;
    try {
      await _evaluateOffline();
    } catch (_) {}
    // Absolute last resort - a screen that explains itself beats an
    // endless splash. PendingApprovalScreen self-corrects when the
    // live snapshot arrives.
    if (state.value == AccessState.checking) {
      state.value = AccessState.pending;
    }
  }

  Future<void> _evaluateFromCache() async {
    // SECURITY (v0.2.21 trust model): SharedPreferences NEVER decides
    // whether an account is valid. The cache is only a SPLASH FAILSAFE
    // for offline launches - the moment any live Firestore verdict
    // arrives (snapshot listener or verifyOnce() on every sync tick)
    // it overrides whatever was cached. A tampered local cache cannot
    // extend a trial, unblock an account or add a device: those fields
    // are server-enforced (firestore.rules v3 - only the Admin Gmail
    // writes them, and shops/{uid} access re-checks status + expiry on
    // EVERY cloud request).
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
    final reg =
        sp.getString('reg_email') ?? sp.getString('reg_phone') ?? '';
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
  final String email; // Google login account (read-only)
  final String phone; // legacy phone-auth accounts, '' otherwise
  final String ownerName;
  final String mobile; // 10-digit shop contact number
  final String city;
  final String address;
  final String gst;
  final String status; // pending | active | blocked
  final String plan; // trial | paid | '' (legacy accounts)
  final int trialStartDate; // ms epoch, 0 = not set
  final DateTime? trialEndDate; // trial ends (7 days after register)
  final DateTime? subscriptionEndDate; // paid validity (Admin / Ruby Key)
  final DateTime? expiryDate; // legacy field, honoured for old accounts
  final int maxDevices;
  List<String> registeredDevices;
  Map<String, String> deviceModels; // deviceId -> model name
  final String pinHash;
  final String pinSalt;

  AccountInfo({
    required this.uid,
    required this.businessName,
    this.email = '',
    this.phone = '',
    this.ownerName = '',
    this.mobile = '',
    this.city = '',
    this.address = '',
    this.gst = '',
    required this.status,
    this.plan = '',
    this.trialStartDate = 0,
    required this.expiryDate,
    this.trialEndDate,
    this.subscriptionEndDate,
    required this.maxDevices,
    required this.registeredDevices,
    Map<String, String>? deviceModels,
    this.pinHash = '',
    this.pinSalt = '',
  }) : deviceModels = deviceModels ?? <String, String>{};

  /// The access spec (v0.3.0): status == "active" AND the admin-set
  /// validity (subscriptionEndDate, or the legacy expiryDate) has not
  /// passed AND this device is one of the (max 2) approved devices.
  /// trialEndDate is deliberately IGNORED - the 7-day trial system was
  /// removed; old accounts with a long-past trialEndDate stay usable.
  DateTime? get effectiveExpiry {
    return subscriptionEndDate ?? expiryDate;
  }

  factory AccountInfo.fromMap(String uid, Map<String, dynamic> m) {
    DateTime? expiry;
    final raw = m['expiryDate'];
    if (raw is Timestamp) expiry = raw.toDate();
    if (raw is int) expiry = DateTime.fromMillisecondsSinceEpoch(raw);
    DateTime? trialEnd;
    final rawTrial = m['trialEndDate'];
    if (rawTrial is Timestamp) trialEnd = rawTrial.toDate();
    if (rawTrial is int) trialEnd = DateTime.fromMillisecondsSinceEpoch(rawTrial);
    DateTime? subEnd;
    final rawSub = m['subscriptionEndDate'];
    if (rawSub is Timestamp) subEnd = rawSub.toDate();
    if (rawSub is int) subEnd = DateTime.fromMillisecondsSinceEpoch(rawSub);
    return AccountInfo(
      uid: uid,
      businessName: (m['businessName'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      ownerName: (m['ownerName'] ?? '') as String,
      mobile: (m['mobile'] ?? '') as String,
      city: (m['city'] ?? '') as String,
      address: (m['address'] ?? '') as String,
      gst: (m['gst'] ?? '') as String,
      status: (m['status'] ?? 'pending') as String,
      plan: (m['plan'] ?? '') as String,
      trialStartDate: ((m['trialStartDate'] ?? 0) as num).toInt(),
      trialEndDate: trialEnd,
      subscriptionEndDate: subEnd,
      expiryDate: expiry,
      maxDevices: ((m['maxDevices'] ?? 2) as num).toInt(),
      registeredDevices: ((m['registeredDevices'] ?? const []) as List)
          .map((e) => e.toString())
          .toList(),
      deviceModels: ((m['deviceModels'] ?? const {}) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      pinHash: (m['pinHash'] ?? '') as String,
      pinSalt: (m['pinSalt'] ?? '') as String,
    );
  }

  /// The exact access rule from the spec, as a pure function:
  /// status == "active" AND the effective validity has not passed AND
  /// this device is one of the (max 2) approved devices.
  AccessState evaluateFor(String deviceId, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (status == 'blocked') return AccessState.blocked;
    if (status != 'active') return AccessState.pending;
    final end = effectiveExpiry;
    if (end != null && t.isAfter(end)) {
      return AccessState.expired;
    }
    if (registeredDevices.contains(deviceId)) return AccessState.allowed;
    if (registeredDevices.length >= maxDevices) return AccessState.deviceLimit;
    return AccessState.allowed; // room left; device will auto-register
  }

  Map<String, dynamic> toMap() => {
        'businessName': businessName,
        'email': email,
        'phone': phone,
        'ownerName': ownerName,
        'mobile': mobile,
        'city': city,
        'address': address,
        'gst': gst,
        'status': status,
        'plan': plan,
        'trialStartDate': trialStartDate,
        'trialEndDate': trialEndDate == null
            ? null
            : Timestamp.fromDate(trialEndDate!),
        'subscriptionEndDate': subscriptionEndDate == null
            ? null
            : Timestamp.fromDate(subscriptionEndDate!),
        'expiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate!),
        'maxDevices': maxDevices,
        'registeredDevices': registeredDevices,
        'deviceModels': deviceModels,
        if (pinHash.isNotEmpty) 'pinHash': pinHash,
        if (pinSalt.isNotEmpty) 'pinSalt': pinSalt,
      };

  Map<String, dynamic> toCache() => {
        'uid': uid,
        'businessName': businessName,
        'email': email,
        'phone': phone,
        'ownerName': ownerName,
        'mobile': mobile,
        'city': city,
        'address': address,
        'gst': gst,
        'status': status,
        'plan': plan,
        'trialStartMs': trialStartDate,
        'trialEndMs': trialEndDate?.millisecondsSinceEpoch,
        'subEndMs': subscriptionEndDate?.millisecondsSinceEpoch,
        'expiryMs': expiryDate?.millisecondsSinceEpoch,
        'maxDevices': maxDevices,
        'registeredDevices': registeredDevices,
        'deviceModels': deviceModels,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
      };

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        uid: (j['uid'] ?? '') as String,
        businessName: (j['businessName'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        ownerName: (j['ownerName'] ?? '') as String,
        mobile: (j['mobile'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        gst: (j['gst'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        plan: (j['plan'] ?? '') as String,
        trialStartDate: ((j['trialStartMs'] ?? 0) as num).toInt(),
        trialEndDate: j['trialEndMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['trialEndMs'] as num).toInt()),
        subscriptionEndDate: j['subEndMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['subEndMs'] as num).toInt()),
        expiryDate: j['expiryMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['expiryMs'] as num).toInt()),
        maxDevices: ((j['maxDevices'] ?? 2) as num).toInt(),
        registeredDevices: ((j['registeredDevices'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        deviceModels: ((j['deviceModels'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        pinHash: (j['pinHash'] ?? '') as String,
        pinSalt: (j['pinSalt'] ?? '') as String,
      );
}
