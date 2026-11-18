import 'package:flutter/material.dart';

/// Ruby brand colors - deep ruby red on white with black ink.
class Ruby {
  static const Color ruby = Color(0xFF9B111E);
  static const Color rubyDark = Color(0xFF7A0D17);
  static const Color rubyLight = Color(0xFFFBE9EB);
  static const Color ink = Color(0xFF141414);
  static const Color muted = Color(0xFF6E6E74);
  static const Color faint = Color(0xFF9A9AA0);
  static const Color line = Color(0xFFE6E6E9);
  static const Color fieldBg = Color(0xFFF7F7F8);
  static const Color green = Color(0xFF0E7C3F);
  static const Color greenLight = Color(0xFFE7F4EC);
}

ThemeData buildRubyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Ruby.ruby,
    brightness: Brightness.light,
  ).copyWith(
    primary: Ruby.ruby,
    secondary: Ruby.ruby,
    surface: Colors.white,
  );

  const radius = BorderRadius.all(Radius.circular(10));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Ruby.ruby,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Ruby.ruby,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ruby.fieldBg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Ruby.line)),
      enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Ruby.line)),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Ruby.ruby, width: 1.6),
      ),
      hintStyle: const TextStyle(color: Ruby.faint, fontSize: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Ruby.ruby,
        foregroundColor: Colors.white,
        minimumSize: const Size(120, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Ruby.ruby,
        side: const BorderSide(color: Ruby.ruby, width: 1.2),
        minimumSize: const Size(120, 48),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Ruby.ruby),
    ),
    dividerTheme: const DividerThemeData(color: Ruby.line, thickness: 1, space: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Ruby.ruby,
      unselectedItemColor: Ruby.faint,
      selectedLabelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 11.5),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Ruby.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
  );
}
