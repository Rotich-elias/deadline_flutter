import 'package:flutter/material.dart';

class Ink0 {
  static const bg = Color(0xFF0E131B);
  static const surface = Color(0xFF171F2B);
  static const surfaceHi = Color(0xFF1F2937);
  static const line = Color(0xFF283344);
  static const text = Color(0xFFE9EEF5);
  static const muted = Color(0xFF8C9AAD);
}

ThemeData buildTheme() {
  const seed = Color(0xFF5C8DEF);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: Ink0.surface,
    ),
    scaffoldBackgroundColor: Ink0.bg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Ink0.text,
      displayColor: Ink0.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Ink0.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: Ink0.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ink0.surfaceHi,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Ink0.surfaceHi,
      contentTextStyle: TextStyle(color: Ink0.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
