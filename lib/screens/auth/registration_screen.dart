import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/access_service.dart';
import '../../services/pin_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// One-time registration: Mobile Number + Business Name + 4-digit Quick PIN.
/// * Firebase configured -> OTP verifies the number, then the account is
///   created in Firestore as users/{uid} with status "pending" - it goes
///   live only after the Admin approves it.
/// * Firebase NOT configured -> local registration with PIN only; the
///   number is stored and OTP + admin approval turn on after setup.
class RegistrationScreen extends StatefulWidget {
  final VoidCallback onDone;
  const RegistrationScreen({super.key, required this.onDone});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _businessC = TextEditingController();
  final _phoneC = TextEditingController();
  final _pinC = TextEditingController();
  final _pin2C = TextEditingController();
  final _otpC = TextEditingController();

  bool get fbReady => SyncService.instance.fbReady;

  String _step = 'details'; // details | otp
  bool _busy = false;
  String? _verificationId;
  int? _resendToken;

  @override
  void dispose() {
    _businessC.dispose();
    _phoneC.dispose();
    _pinC.dispose();
    _pin2C.dispose();
    _otpC.dispose();
    super.dispose();
  }

  Future<void> _submitDetails() async {
    final business = _businessC.text.trim();
    final phone = _phoneC.text.trim();
    final pin = _pinC.text.trim();
    final pin2 = _pin2C.text.trim();
    if (business.isEmpty) {
      showSnack(context, 'Enter your business name', error: true);
      return;
    }
    if (phone.length != 10 || int.tryParse(phone) == null) {
      showSnack(context, 'Enter a valid 10-digit mobile number', error: true);
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

    if (!fbReady) {
      await _finishRegistration(phone);
      return;
    }

    setState(() => _busy = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$phone',
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential cred) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(cred);
          await _finishRegistration(phone);
        } catch (e) {
          _error('Auto verification failed: $e');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        _error(e.message ?? 'Verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _step = 'otp';
          _busy = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpC.text.trim();
    if (code.length < 6) {
      showSnack(context, 'Enter the 6-digit OTP', error: true);
      return;
    }
    if (_verificationId == null) return;
    setState(() => _busy = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      await _finishRegistration(_phoneC.text.trim());
    } on FirebaseAuthException catch (e) {
      _error(e.message ?? 'Invalid OTP');
    } catch (e) {
      _error('Could not verify: $e');
    }
  }

  Future<void> _finishRegistration(String phone) async {
    // PIN hash first (salted SHA-256, never the plain PIN).
    await PinService.instance.setPin(_pinC.text.trim());

    if (SyncService.instance.fbReady) {
      // Create / attach the master account: users/{uid} with
      // status "pending" until the Admin approves it.
      final stored = await PinService.instance.stored;
      try {
        await AccessService.instance.registerUser(
          phone: '+91$phone',
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
    await sp.setString('reg_phone', phone);
    try {
      await Repo.instance.setMeta('shop_name', _businessC.text.trim());
    } catch (_) {}
    SyncService.instance.syncSoon();
    if (!mounted) return;
    showSnack(
      context,
      SyncService.instance.fbReady
          ? 'Registered! Waiting for Admin approval'
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
                _step == 'details'
                    ? 'Register with your mobile number'
                    : 'OTP sent to +91 ${_phoneC.text.trim()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Ruby.muted),
              ),
              const SizedBox(height: 26),
              if (_step == 'details') _detailsCard() else _otpCard(),
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
              'Firebase is not configured yet - OTP verification is off. '
              'The app will register with your number + PIN only. '
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
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: Ruby.fieldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Ruby.line),
              ),
              child: const Text('+91', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Ruby.ink)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _phoneC,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(10)],
                decoration: const InputDecoration(hintText: 'Mobile number', isDense: false),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
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
        ElevatedButton(
          onPressed: _busy ? null : _submitDetails,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(fbReady ? 'Send OTP & Register' : 'Register'),
        ),
      ],
    );
  }

  Widget _otpCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _otpC,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          autofocus: true,
          style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(hintText: '- - - - - -', isDense: false),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _verifyOtp,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify OTP'),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _busy ? null : _submitDetails,
              child: const Text('Resend OTP'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _step = 'details';
                        _otpC.clear();
                      });
                    },
              child: const Text('Change number'),
            ),
          ],
        ),
      ],
    );
  }
}
