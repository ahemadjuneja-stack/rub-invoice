import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/access_service.dart';
import '../../services/pin_service.dart';
import '../../services/sync_service.dart';
import '../home/home_screen.dart';
import '../lock/access_locked_screen.dart';
import '../lock/pending_approval_screen.dart';
import 'pin_lock_screen.dart';
import 'registration_screen.dart';

/// Decides what the user sees first. Two regimes:
///
/// FIREBASE MODE (configured):
///   1. not signed in            -> RegistrationScreen (mobile + OTP)
///   2. signed in, status pending-> PendingApprovalScreen (admin must approve)
///   3. signed in, blocked/expired/deviceLimit -> AccessLockedScreen
///   4. signed in, allowed       -> Quick PIN unlock -> HomeScreen
///   The access state comes from a LIVE users/{uid} listener, so an
///   admin kill-switch locks the app instantly, even mid-session.
///
/// OFFLINE MODE (Firebase not configured):
///   registered locally + PIN -> HomeScreen (no admin gate exists).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _localRegistered = false; // offline mode only
  bool _hasPin = false;
  bool _unlocked = false;

  late final AccessService _access;
  FirebaseAuth? _fb;
  bool _listenersBound = false;

  @override
  void initState() {
    super.initState();
    _access = AccessService.instance;
    _access.state.addListener(_onAccessChanged);
    _bindFirebase();
    _load();
  }

  @override
  void dispose() {
    _access.state.removeListener(_onAccessChanged);
    super.dispose();
  }

  /// Re-reads local registration state. Safe to call any time; the
  /// Firebase listeners are bound exactly once (in initState).
  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _localRegistered = (sp.getString('reg_phone') ?? '').isNotEmpty;
    _hasPin = await PinService.instance.hasPin;
    if (mounted) setState(() => _loading = false);
    if (!SyncService.instance.fbReady) {
      SyncService.instance.syncSoon();
    }
  }

  void _bindFirebase() {
    if (_listenersBound) return;
    _listenersBound = true;
    if (SyncService.instance.fbReady) {
      try {
        _fb = FirebaseAuth.instance;
        _fb!.authStateChanges().listen((user) {
          if (user != null) {
            _access.startWatching(); // live kill-switch + offline cache
            SyncService.instance.syncSoon();
          } else {
            _access.stopWatching();
            _access.state.value = AccessState.signedOut;
          }
          _unlocked = false;
          if (mounted) setState(() {});
        });
      } catch (_) {
        _fb = null;
      }
    } else {
      _access.state.value = AccessState.allowed; // pure offline mode
    }
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  /// When access is allowed: make sure the Quick PIN exists locally.
  /// On a 2nd device the PIN is imported from the account record, so
  /// the same mobile number + PIN unlocks both phones.
  Future<void> _ensureLocalPin() async {
    if (_hasPin) return;
    final info = _access.account.value;
    if (info == null) return;
    final imported = await PinService.instance
        .importFrom(salt: info.pinSalt, hashValue: info.pinHash);
    if (imported) {
      _hasPin = true;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _splash();

    // ---------- OFFLINE MODE ----------
    final fbSignedIn = _fb?.currentUser != null;
    if (!SyncService.instance.fbReady || !fbSignedIn) {
      if (!SyncService.instance.fbReady) {
        if (!_localRegistered) return RegistrationScreen(onDone: _load);
        if (_hasPin && !_unlocked) {
          return PinLockScreen(onUnlocked: () => setState(() => _unlocked = true));
        }
        return const HomeScreen();
      }
      // Firebase configured but not signed in yet.
      return RegistrationScreen(onDone: _load);
    }

    // ---------- FIREBASE MODE: the admin gate ----------
    switch (_access.state.value) {
      case AccessState.checking:
        return _splash();
      case AccessState.signedOut:
        return RegistrationScreen(onDone: _load);
      case AccessState.pending:
        return const PendingApprovalScreen();
      case AccessState.blocked:
      case AccessState.expired:
      case AccessState.deviceLimit:
        return AccessLockedScreen(reason: _access.state.value);
      case AccessState.allowed:
        _ensureLocalPin();
        if (_hasPin && !_unlocked) {
          return PinLockScreen(onUnlocked: () => setState(() => _unlocked = true));
        }
        return const HomeScreen();
    }
  }

  Widget _splash() {
    return Scaffold(
      backgroundColor: Ruby.ruby,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.receipt_long, color: Colors.white, size: 54),
            SizedBox(height: 12),
            Text(
              'RUBY INVOICE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Fast billing. Zero mistakes.',
              style: TextStyle(color: Color(0xFFF6C9CD), fontSize: 12.5, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
