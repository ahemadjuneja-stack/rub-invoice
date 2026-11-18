import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/pin_service.dart';
import '../../services/sync_service.dart';
import '../home/home_screen.dart';
import 'pin_lock_screen.dart';
import 'registration_screen.dart';

/// Decides what the user sees first:
///  1. nothing registered -> RegistrationScreen (mobile + OTP when
///     Firebase is configured, otherwise local PIN only)
///  2. registered + PIN set -> PinLockScreen every app start
///  3. registered, no PIN -> straight to HomeScreen
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _registered = false;
  bool _hasPin = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final registered = (sp.getString('reg_phone') ?? '').isNotEmpty;
    final hasPin = await PinService.instance.hasPin;
    if (!mounted) return;
    setState(() {
      _registered = registered;
      _hasPin = hasPin;
      _unlocked = !hasPin;
      _loading = false;
    });
    // Kick a background sync as soon as the app opens (if configured).
    SyncService.instance.syncSoon();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _splash();
    if (!_registered) {
      return RegistrationScreen(onDone: _load);
    }
    if (_hasPin && !_unlocked) {
      return PinLockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    return const HomeScreen();
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
