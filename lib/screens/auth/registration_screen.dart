import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/access_service.dart';
import '../../services/pin_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/widgets.dart';

/// STEP 2 of the login flow: the Business Registration screen.
///
/// Opened right after a NEW Gmail signs in (the email comes from Google
/// and is shown read-only). Collects the shop details required by the
/// access spec - Shop Name, Owner Name, 10-digit Mobile, City, Address
/// and optional GST - plus the 4-digit Quick PIN (existing UX), then
/// creates the account in Firestore `users/{uid}` with:
///   status: active (auto_approve) | pending, plan: "trial",
///   trialStartDate: now, trialEndDate: now + 7 days, maxDevices: 2.
///
/// On submit the owner lands STRAIGHT on the main dashboard - there is
/// no waiting / pending screen when auto-approve is on.
///
/// OFFLINE MODE (Firebase not configured): the same form registers
/// locally with the PIN only (no Firestore write).
class RegistrationScreen extends StatefulWidget {
  final String prefilledEmail; // '' in offline mode
  final VoidCallback onDone;
  const RegistrationScreen({
    super.key,
    this.prefilledEmail = '',
    required this.onDone,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _businessC = TextEditingController();
  final _ownerC = TextEditingController();
  final _mobileC = TextEditingController();
  final _cityC = TextEditingController();
  final _addrC = TextEditingController();
  final _gstC = TextEditingController();
  final _pinC = TextEditingController();
  final _pin2C = TextEditingController();

  bool get fbReady => SyncService.instance.fbReady;

  bool _busy = false;

  @override
  void dispose() {
    _businessC.dispose();
    _ownerC.dispose();
    _mobileC.dispose();
    _cityC.dispose();
    _addrC.dispose();
    _gstC.dispose();
    _pinC.dispose();
    _pin2C.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final business = _businessC.text.trim();
    final owner = _ownerC.text.trim();
    final mobile = _mobileC.text.trim();
    final city = _cityC.text.trim();
    final addr = _addrC.text.trim();
    final gst = _gstC.text.trim();
    final pin = _pinC.text.trim();
    final pin2 = _pin2C.text.trim();

    if (business.isEmpty) {
      showSnack(context, 'Enter your business name', error: true);
      return;
    }
    if (owner.isEmpty) {
      showSnack(context, 'Enter the owner name', error: true);
      return;
    }
    if (mobile.length != 10 || int.tryParse(mobile) == null) {
      showSnack(context, 'Mobile number must be exactly 10 digits', error: true);
      return;
    }
    if (city.isEmpty) {
      showSnack(context, 'Enter your city', error: true);
      return;
    }
    if (addr.isEmpty) {
      showSnack(context, 'Enter your shop address', error: true);
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
      await PinService.instance.setPin(pin);

      if (fbReady && widget.prefilledEmail.isNotEmpty) {
        final stored = await PinService.instance.stored;
        try {
          await AccessService.instance.registerUser(
            email: widget.prefilledEmail,
            businessName: business,
            ownerName: owner,
            mobile: mobile,
            city: city,
            address: addr,
            gst: gst,
            pinHash: stored.hash,
            pinSalt: stored.salt,
          );
        } catch (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          showSnack(context, 'Could not create account: $e', error: true);
          return;
        }
      }

      // Remember registration locally + use the business name on bills.
      final sp = await SharedPreferences.getInstance();
      await sp.setString('reg_email', widget.prefilledEmail);
      await sp.setString('reg_phone', mobile);
      try {
        await Repo.instance.setMeta('shop_name', business);
      } catch (_) {}
      SyncService.instance.syncSoon();
      if (!mounted) return;
      showSnack(
        context,
        fbReady
            ? 'Business registered! Ruby Invoice is ready'
            : 'Registered. Ruby Invoice is ready!',
      );
      widget.onDone();
    } catch (e) {
      // v0.2.19: registration must never die silently (PIN save, prefs).
      debugPrint('[registration] failed: $e');
      if (mounted) {
        showSnack(context, 'Registration failed - please try again',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: fbReady && widget.prefilledEmail.isNotEmpty
          ? AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text(
                'Business Registration',
                style: TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w800, color: Ruby.ink),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!(fbReady && widget.prefilledEmail.isNotEmpty)) ...[
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
              ],
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
        if (fbReady && widget.prefilledEmail.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Ruby.fieldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Ruby.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email, size: 18, color: Ruby.ruby),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.prefilledEmail,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Ruby.ink),
                  ),
                ),
                const Text(
                  'from Google',
                  style: TextStyle(fontSize: 10.5, color: Ruby.faint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This Gmail is your login and stays read-only.',
            style: TextStyle(fontSize: 11, color: Ruby.faint),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _businessC,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Shop / Business name *', isDense: false),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ownerC,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Owner name *', isDense: false),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _mobileC,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'\d')),
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(hintText: 'Mobile number (10 digits) *', isDense: false),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cityC,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'City *', isDense: false),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _addrC,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Shop address *', isDense: false),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _gstC,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'GST number (optional)', isDense: false),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pinC,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(hintText: 'Set 4-digit PIN *', isDense: false),
          style: const TextStyle(fontSize: 15, letterSpacing: 6),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin2C,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d')), LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(hintText: 'Confirm PIN *', isDense: false),
          style: const TextStyle(fontSize: 15, letterSpacing: 6),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('REGISTER & START BILLING',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        Text(
          fbReady
              ? 'New accounts start with a FREE 7-day trial. 2 devices max.'
              : 'Offline mode: registration stays on this phone only.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, height: 1.45, color: Ruby.faint),
        ),
      ],
    );
  }
}
