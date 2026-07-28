import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.line,
    required this.text,
    required this.muted,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color line;
  final Color text;
  final Color muted;
}

const _darkPalette = _Palette(
  bg: Color(0xFF0E131B),
  surface: Color(0xFF171F2B),
  surfaceHi: Color(0xFF1F2937),
  line: Color(0xFF283344),
  text: Color(0xFFE9EEF5),
  muted: Color(0xFF8C9AAD),
);

const _lightPalette = _Palette(
  bg: Color(0xFFF5F6F8),
  surface: Color(0xFFFFFFFF),
  surfaceHi: Color(0xFFEEF0F3),
  line: Color(0xFFDCE0E6),
  text: Color(0xFF15181D),
  muted: Color(0xFF676F7E),
);

/// Colour lookup used throughout the UI in place of `Theme.of(context)`.
/// [AppTheme] keeps [_active] pointed at the right palette before each
/// build, so a plain static read here always reflects the current light/
/// dark mode without every widget needing a BuildContext for it.
class Ink0 {
  Ink0._();

  static _Palette _active = _darkPalette;

  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get surfaceHi => _active.surfaceHi;
  static Color get line => _active.line;
  static Color get text => _active.text;
  static Color get muted => _active.muted;
}

/// Persists and broadcasts the user's light/dark/system preference.
class AppTheme extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  static const _prefKey = 'appearance.mode';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = switch (prefs.getString(_prefKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == mode) return;
    mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  /// Call once per build, before any descendant reads [Ink0], so the two
  /// stay in lockstep with whatever [MaterialApp] resolves to.
  void syncPalette(Brightness platformBrightness) {
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    Ink0._active = dark ? _darkPalette : _lightPalette;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? _darkPalette : _lightPalette;
  const seed = Color(0xFF5C8DEF);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: palette.surface,
    ),
    scaffoldBackgroundColor: palette.bg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: palette.text,
      displayColor: palette.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: palette.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceHi,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHi,
      contentTextStyle: TextStyle(color: palette.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
