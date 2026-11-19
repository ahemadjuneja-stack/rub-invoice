import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/theme.dart';
import '../../widgets/widgets.dart';
import 'registration_screen.dart';

/// STEP 1 of the login flow (the access spec):
/// a clean screen with the Ruby Invoice logo and a single
/// "Continue with Google" button. Nothing else.
///
/// After the Google account is picked:
///   * users/{uid} EXISTS  -> straight to the app (the live access check
///     in AuthGate decides pending / locked / PIN / home).
///   * users/{uid} MISSING -> the Business Registration screen opens
///     immediately (email is auto-filled and read-only there).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
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

      // Account check: users/{uid} in Firestore.
      final uid = userCred.user!.uid;
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      if (snap.exists) {
        // Existing account: the authStateChanges listener in AuthGate
        // re-runs the full access check (status / validity / devices)
        // and routes to the right screen. Nothing else to do here.
        if (mounted) setState(() => _busy = false);
        return;
      }
      // New Gmail -> Business Registration immediately (no waiting).
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RegistrationScreen(
          prefilledEmail: email,
          onDone: () => Navigator.of(context).pop(),
        ),
      ));
      if (mounted) setState(() => _busy = false);
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandMark(markHeight: 110),
                const SizedBox(height: 10),
                const Text(
                  'Fast billing. Zero mistakes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Ruby.muted),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _continueWithGoogle,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.mail_outline, size: 20),
                  label: Text(
                    _busy ? 'Signing in...' : 'Continue with Google',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use the Gmail account of your shop. No OTP, no SMS - '
                  'one tap and you are in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: Ruby.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
