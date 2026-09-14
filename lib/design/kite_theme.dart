import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kite/design/kite_tokens.dart';

enum KiteDarkThemeVariant { standard, trueBlack }

abstract final class KiteSystemBars {
  static SystemUiOverlayStyle forTheme(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: theme.scaffoldBackgroundColor,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }
}

abstract final class KiteTheme {
  static const _seed = Color(0xFF0B7A6B);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);
  static final ThemeData black = _build(Brightness.dark, trueBlack: true);

  static void warmUp() {
    light;
    dark;
    black;
  }

  static ThemeData _build(Brightness brightness, {bool trueBlack = false}) {
    var scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    if (trueBlack) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF050505),
        surfaceContainer: const Color(0xFF090909),
        surfaceContainerHigh: const Color(0xFF0D0D0D),
        surfaceContainerHighest: const Color(0xFF151515),
      );
    }
    var tokens = KiteSemanticColors.forBrightness(brightness, scheme);
    if (trueBlack) {
      tokens = tokens.copyWith(
        canvas: Colors.black,
        navigation: Colors.black,
        field: const Color(0xFF0D0D0D),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      dividerColor: scheme.outlineVariant.withValues(
        alpha: KiteOpacity.divider,
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        elevation: KiteElevation.flat,
        scrolledUnderElevation: KiteElevation.flat,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size.square(KiteSizes.minimumTouchTarget),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, KiteSizes.minimumTouchTarget),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KiteRadii.lg),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, KiteSizes.minimumTouchTarget),
          ),
        ),
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
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: KiteSpacing.xs,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.navigation,
        indicatorColor: tokens.selected,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: KiteElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainer,
        elevation: KiteElevation.floating,
        modalElevation: KiteElevation.overlay,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KiteRadii.lg),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        elevation: KiteElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiteRadii.md),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          elevation: const WidgetStatePropertyAll(KiteElevation.overlay),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KiteRadii.md),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: KiteElevation.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiteRadii.sm),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(KiteRadii.sm),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}
