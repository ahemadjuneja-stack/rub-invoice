import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/home/home_screen.dart';

/// LOGIN IS CURRENTLY DISABLED (build phase).
///
/// When [kLoginEnabled] is false the app opens straight to the
/// HomeScreen: no Google sign-in, no registration screen, no PIN lock,
/// no admin approval gate. Every login screen and service stays in the
/// repo untouched - flip this single constant back to `true` to restore
/// the complete login flow (AuthGate then decides between registration,
/// pending approval, locked and PIN screens as before).
const bool kLoginEnabled = false;

class RubyInvoiceApp extends StatelessWidget {
  const RubyInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ruby Invoice',
      debugShowCheckedModeBanner: false,
      theme: buildRubyTheme(),
      home: kLoginEnabled ? const AuthGate() : const HomeScreen(),
    );
  }
}
