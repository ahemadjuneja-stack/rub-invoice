import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/pin_service.dart';

/// Daily unlock screen: 4-digit PIN with a big numeric keypad.
class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinLockScreen({super.key, required this.onUnlocked});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _entered = '';
  bool _error = false;
  String _phone = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _phone = sp.getString('reg_phone') ?? '');
    });
  }

  void _tap(String d) {
    if (_entered.length >= 4 || _error) return;
    final next = _entered + d;
    setState(() => _entered = next);
    if (next.length == 4) _check();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _check() async {
    final ok = await PinService.instance.verify(_entered);
    if (ok) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _error = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (mounted) {
      setState(() {
        _entered = '';
        _error = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(
              _error ? Icons.lock_open : Icons.lock_outline,
              size: 44,
              color: _error ? Colors.red : Ruby.ruby,
            ),
            const SizedBox(height: 12),
            Text(
              _error ? 'Wrong PIN. Try again' : 'Enter PIN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _error ? Colors.red : Ruby.ink,
              ),
            ),
            if (_phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+91 $_phone', style: const TextStyle(fontSize: 12.5, color: Ruby.muted)),
              ),
            const SizedBox(height: 22),
            _dots(),
            const Spacer(flex: 2),
            _keypad(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < _entered.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? (_error ? Colors.red : Ruby.ruby) : Colors.white,
            border: Border.all(color: _error ? Colors.red : Ruby.ruby, width: 1.8),
          ),
        );
      }),
    );
  }

  Widget _keypad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '<'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (final key in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: _key(key),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(String k) {
    if (k.isEmpty) return const SizedBox(height: 64);
    if (k == '<') {
      return SizedBox(
        height: 64,
        child: TextButton(
          onPressed: _backspace,
          style: TextButton.styleFrom(
            backgroundColor: Ruby.fieldBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Icon(Icons.backspace_outlined, size: 22, color: Ruby.ink),
        ),
      );
    }
    return SizedBox(
      height: 64,
      child: TextButton(
        onPressed: () => _tap(k),
        style: TextButton.styleFrom(
          backgroundColor: Ruby.fieldBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          k,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Ruby.ink),
        ),
      ),
    );
  }
}
