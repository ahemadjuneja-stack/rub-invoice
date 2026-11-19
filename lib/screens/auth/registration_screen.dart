import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/access_service.dart';
import '../../services/pin_service.dart';
import '../../services/remote_config.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// One-time registration: Google account + Business Name + 4-digit PIN.
/// * Firebase configured -> sign in with the phone's Gmail (no SMS at
///   all - OTP was removed because Indian SMS delivery is unreliable),
///   then the account is created in Firestore as users/{uid}. While the
///   remote `auto_approve` flag is ON the account is born active.
/// * Firebase NOT configured -> local registration with PIN only.
class RegistrationScreen extends StatefulWidget {
  final VoidCallback onDone;
  const RegistrationScreen({super.key, required this.onDone});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _businessC = TextEditingController();
  final _pinC = TextEditingController();
  final _pin2C = TextEditingController();

  bool get fbReady => SyncService.instance.fbReady;

  bool _busy = false;

  @override
  void dispose() {
    _businessC.dispose();
    _pinC.dispose();
    _pin2C.dispose();
    super.dispose();
  }

  Future<void> _registerWithGoogle() async {
    final business = _businessC.text.trim();
    final pin = _pinC.text.trim();
    final pin2 = _pin2C.text.trim();
    if (business.isEmpty) {
      showSnack(context, 'Enter your business name', error: true);
      return;
    }
    if (pin.length != 4 || int.tryParse(pin) == null) {
      showSnack(context, 'PIN must be exactly 4 digits', error: true);
      return;
    }
    if (pin != pin2) {
      showSnack(context, 'PINs do not match', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final google = GoogleSignIn();
      final account = await google.signIn(); // account picker
      if (account == null) {
        // user closed the picker - not an error
        if (mounted) setState(() => _busy = false);
        return;
      }
      final auth = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
      final email = userCred.user?.email ?? account.email;
      await _finishRegistration(email);
    } on PlatformException catch (e) {
      _error(_friendlyGoogleError(e));
    } on FirebaseAuthException catch (e) {
      _error(e.message ?? 'Google sign-in failed (${e.code})');
    } catch (e) {
      _error('Google sign-in failed: $e');
    }
  }

  /// google_sign_in raises PlatformException with numeric codes. Map the
  /// common ones to what the shop owner should actually DO.
  String _friendlyGoogleError(PlatformException e) {
    switch (e.code) {
      case '12501':
        return 'Google sign-in was cancelled. Tap the button and pick '
            'your Gmail account.';
      case '10':
        return 'Setup incomplete: add the app SHA-1 / SHA-256 fingerprints '
            'in Firebase console (Project settings -> Your apps) and '
            're-download google-services.json (docs/FIREBASE_SETUP.md).';
      case '7':
        return 'No internet connection. Check mobile data or WiFi.';
      case '8':
        return 'Google sign-in hit an internal error. Try again in a '
            'minute.';
      default:
        return 'Google sign-in failed (${e.code}). Try again.';
    }
  }

  Future<void> _finishRegistration(String email) async {
    // PIN hash first (salted SHA-256, never the plain PIN).
    await PinService.instance.setPin(_pinC.text.trim());

    if (SyncService.instance.fbReady) {
      // Create / attach the master account: users/{uid}. Born "active"
      // while auto_approve is ON, "pending" otherwise.
      final stored = await PinService.instance.stored;
      try {
        await AccessService.instance.registerUser(
          email: email,
          businessName: _businessC.text.trim(),
          pinHash: stored.hash,
          pinSalt: stored.salt,
        );
      } catch (e) {
        _error('Could not create account: $e');
        return;
      }
    }

    // Remember registration locally + use the business name on bills.
    final sp = await SharedPreferences.getInstance();
    await sp.setString('reg_email', email);
    try {
      await Repo.instance.setMeta('shop_name', _businessC.text.trim());
    } catch (_) {}
    SyncService.instance.syncSoon();
    if (!mounted) return;
    final auto = RemoteConfigService.instance.config.value.autoApprove;
    showSnack(
      context,
      SyncService.instance.fbReady
          ? (auto
              ? 'Registered! Ruby Invoice is ready'
              : 'Registered! Waiting for Admin approval')
          : 'Registered. Ruby Invoice is ready!',
    );
    widget.onDone();
  }

  void _error(String msg) {
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, msg, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandMark(markHeight: 88),
              const SizedBox(height: 12),
              Text(
                fbReady
                    ? 'Register with your Gmail account'
                    : 'Register to start billing',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Ruby.muted),
              ),
              const SizedBox(height: 26),
              _detailsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fbReady)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE7D9A8)),
            ),
            child: const Text(
              'Firebase is not configured yet - Google sign-in is off. '
              'The app will register with your name + PIN only. '
              'Setup: docs/FIREBASE_SETUP.md',
              style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF7A6414)),
            ),
          ),
        TextField(
          controller: _businessC,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Business name', isDense: false),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pinC,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(hintText: 'Set 4-digit PIN', isDense: false),
          style: const TextStyle(fontSize: 15, letterSpacing: 6),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin2C,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(hintText: 'Confirm PIN', isDense: false),
          style: const TextStyle(fontSize: 15, letterSpacing: 6),
        ),
        const SizedBox(height: 24),
        if (fbReady)
          ElevatedButton.icon(
            onPressed: _busy ? null : _registerWithGoogle,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.mail_outline, size: 20),
            label: Text(_busy ? 'Signing in...' : 'Sign in with Google & Register'),
          )
        else
          ElevatedButton(
            onPressed: _busy ? null : () async => _finishRegistration(''),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Register'),
          ),
        if (fbReady) ...[
          const SizedBox(height: 10),
          const Text(
            'No OTP, no SMS - picks your Gmail in one tap.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: Ruby.faint),
          ),
        ],
      ],
    );
  }
}
