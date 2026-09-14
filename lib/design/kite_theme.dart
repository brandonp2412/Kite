import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';

abstract final class KiteTheme {
  static const _seed = Color(0xFF0B7A6B);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final tokens = KiteSemanticColors.forBrightness(brightness, scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      dividerColor: scheme.outlineVariant.withValues(
        alpha: KiteOpacity.divider,
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
        headlineSmall: KiteTypography.headline.copyWith(
          color: scheme.onSurface,
        ),
        titleMedium: KiteTypography.title.copyWith(color: scheme.onSurface),
        bodyMedium: KiteTypography.body.copyWith(color: scheme.onSurface),
        bodySmall: KiteTypography.metadata.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: KiteElevation.flat,
        scrolledUnderElevation: KiteElevation.flat,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
          borderSide: BorderSide.none,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.navigation,
        indicatorColor: tokens.selected,
      ),
    );
  }
}
