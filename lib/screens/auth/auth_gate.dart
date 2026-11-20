import 'dart:async';
import '../../core/app_log.dart';

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
import 'login_screen.dart';
import 'pin_lock_screen.dart';
import 'registration_screen.dart';

/// Decides what the user sees first. Two regimes:
///
/// FIREBASE MODE (configured):
///   1. not signed in            -> LoginScreen (Continue with Google);
///                                  a NEW Gmail opens the Business
///                                  Registration screen immediately
///   2. signed in, status pending-> PendingApprovalScreen (admin must approve)
///   3. signed in, blocked/expired/deviceLimit -> AccessLockedScreen
///   4. signed in, allowed       -> Quick PIN unlock -> HomeScreen
///   The access state comes from a LIVE users/{uid} listener, so an
///   admin kill-switch locks the app instantly, even mid-session.
///
/// OFFLINE MODE (Firebase not configured):
///   registered locally + PIN -> HomeScreen (no admin gate exists).
///
/// SPLASH FAILSAFE: a strict 3-second timer guarantees the splash
/// ALWAYS resolves - to the Login screen when currentUser is null
/// (e.g. right after Clear Data) or to the cached access verdict
/// otherwise - even if authStateChanges never emits, the user
/// profile fetch hangs, or any startup error is thrown.
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

  /// SPLASH FAILSAFE (fix: infinite splash after Clear Data): fires
  /// exactly 3 seconds after initState. By then the auth state has
  /// almost certainly emitted; if it has not, the timer resolves the
  /// splash itself instead of waiting on Firebase / the network.
  Timer? _failsafe;

  /// v0.2.19: Firebase can come alive AFTER boot (background recovery
  /// on a slow network). When it does, re-evaluate the routing so the
  /// login screen / cloud sync appear without a restart.
  void _onFbReadyFlip() {
    if (!mounted) return;
    _listenersBound = false; // re-bind Firebase listeners for the new mode
    _bindFirebase();
    unawaited(_load());
  }

  /// Set on the first authStateChanges emission. Until then a Firebase
  /// login is being RESTORED (this survives APK updates) - the splash
  /// must stay up instead of flashing the registration screen.
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    _access = AccessService.instance;
    _access.state.addListener(_onAccessChanged);
    SyncService.instance.fbReadyNotifier.addListener(_onFbReadyFlip);
    _bindFirebase();
    _load();
    // Strict 3-second maximum: SplashScreen.hide() / the first real
    // screen ALWAYS appears within 3 seconds, no matter how slow or
    // broken Firebase / the network is.
    _failsafe = Timer(const Duration(seconds: 3), _failsafeTimeout);
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _access.state.removeListener(_onAccessChanged);
    SyncService.instance.fbReadyNotifier.removeListener(_onFbReadyFlip);
    super.dispose();
  }

  /// The splash can no longer outlive this method.
  void _failsafeTimeout() {
    if (!mounted) return;
    appLog('AuthGate failsafe fired - resolving splash after 3s');
    // Stop waiting for authStateChanges: with no Firebase session
    // (exactly the case right after Clear Data) the build below now
    // shows the Login screen immediately.
    _authChecked = true;
    _loading = false;
    setState(() {});
    // Signed in but the users/{uid} verdict is still "checking"?
    // Resolve from the cached snapshot / local marks - never hang.
    if (SyncService.instance.fbReady &&
        _fb?.currentUser != null &&
        _access.state.value == AccessState.checking) {
      unawaited(_access.resolveFromCacheNow());
    }
  }

  /// Re-reads local registration state. Safe to call any time; the
  /// Firebase listeners are bound exactly once (in initState).
  /// Every failure lands in the finally block, so the splash ALWAYS
  /// ends - an error here can never leave the app stuck on startup.
  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _localRegistered = (sp.getString('reg_email') ??
              sp.getString('reg_phone') ??
              '')
          .isNotEmpty;
      _hasPin = await PinService.instance.hasPin;
      if (!SyncService.instance.fbReady) {
        SyncService.instance.syncSoon();
      }
    } catch (e) {
      appLog('local auth-state load failed: $e');
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  void _bindFirebase() {
    if (_listenersBound) return;
    _listenersBound = true;
    if (SyncService.instance.fbReady) {
      try {
        _fb = FirebaseAuth.instance;
        _fb!.authStateChanges().listen((user) {
          try {
            _authChecked = true;
            if (user != null) {
              _access.startWatching(); // live kill-switch + offline cache
              SyncService.instance.syncSoon();
            } else {
              _access.stopWatching();
              _access.state.value = AccessState.signedOut;
            }
          } catch (e) {
            // user profile fetch / listener setup failed (offline,
            // Clear Data, permissions): never keep the splash waiting.
            appLog('auth state handling failed: $e');
            if (_access.state.value == AccessState.checking) {
              unawaited(_access.resolveFromCacheNow());
            }
          } finally {
            _unlocked = false;
            if (mounted) setState(() {});
          }
        }, onError: (Object e) {
          // The auth STREAM itself errored - treat it like signed-out
          // and let the failsafe / first emission recover later.
          appLog('authStateChanges stream error: $e');
          _authChecked = true;
          if (_access.state.value == AccessState.checking) {
            unawaited(_access.resolveFromCacheNow());
          }
          if (mounted) setState(() {});
        });
      } catch (e) {
        appLog('FirebaseAuth unavailable: $e');
        _fb = null;
        // Do NOT wait for a stream that will never be bound.
        _authChecked = true;
        if (mounted) setState(() {});
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
    final fbReady = SyncService.instance.fbReady;
    final fbSignedIn = _fb?.currentUser != null;
    if (!fbReady) {
      if (!_localRegistered) return RegistrationScreen(onDone: _load);
      if (_hasPin && !_unlocked) {
        return PinLockScreen(onUnlocked: () => setState(() => _unlocked = true));
      }
      return const HomeScreen();
    }
    // Firebase mode. A saved session survives APK updates (same signing
    // key + Firebase auto-persistence), so while the auth state has not
    // emitted yet we keep the splash up - never flash registration.
    if (!fbSignedIn && !_authChecked) return _splash(restoring: true);
    if (!fbSignedIn) {
      // Firebase configured but genuinely signed out -> STEP 1:
      // the clean login screen (logo + Continue with Google). It runs
      // the account check itself: existing Gmail goes straight in,
      // a NEW Gmail opens the Business Registration screen (STEP 2).
      return const LoginScreen();
    }

    // ---------- FIREBASE MODE: the admin gate ----------
    switch (_access.state.value) {
      case AccessState.checking:
        return _splash();
      case AccessState.signedOut:
        return const LoginScreen();
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

  Widget _splash({bool restoring = false}) {
    final subtitle = restoring
        ? 'Restoring your login...'
        : 'Fast billing. Zero mistakes.';
    return Scaffold(
      backgroundColor: Ruby.ruby,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, color: Colors.white, size: 54),
            const SizedBox(height: 12),
            const Text(
              'RUBY INVOICE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                  color: Color(0xFFF6C9CD),
                  fontSize: 12.5,
                  letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
