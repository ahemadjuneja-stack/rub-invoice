import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';

class RubyInvoiceApp extends StatelessWidget {
  const RubyInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ruby Invoice',
      debugShowCheckedModeBanner: false,
      theme: buildRubyTheme(),
      home: const AuthGate(),
    );
  }
}
