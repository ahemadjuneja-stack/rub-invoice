import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/home/home_screen.dart';

/// LOGIN IS ENABLED: Google sign-in (no SMS) -> account check ->
/// Business Registration for NEW Gmails -> 7-day trial -> Quick PIN ->
/// Home. The whole flow lives in AuthGate; set this to false only to
/// build/test the app without any login screens.
const bool kLoginEnabled = true;

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
