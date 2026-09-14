import 'package:flutter/material.dart';

abstract final class KiteTheme {
  static const _seed = Color(0xFF0B7A6B);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF111513)
          : const Color(0xFFF7F8F7),
      dividerColor: scheme.outlineVariant.withValues(alpha: .55),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1B201E) : const Color(0xFFEEF1EF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark
            ? const Color(0xFF0D100F)
            : const Color(0xFFF1F3F2),
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
