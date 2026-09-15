import 'package:flutter/material.dart';

abstract final class KiteTypography {
  static const String fallbackFamily = 'Roboto';

  static const TextStyle headline = TextStyle(
    fontFamily: fallbackFamily,
    fontSize: 22,
    height: 1.18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const TextStyle title = TextStyle(
    fontFamily: fallbackFamily,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: fallbackFamily,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle metadata = TextStyle(
    fontFamily: fallbackFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );
}

abstract final class KiteSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class KiteRadii {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double pill = 999;
}

abstract final class KiteLayout {
  static const double readableContentMaxWidth = 720;

  static double centeredHorizontalInset(
    BuildContext context, {
    double maxWidth = readableContentMaxWidth,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return width > maxWidth ? (width - maxWidth) / 2 : 0;
  }
}

abstract final class KiteElevation {
  static const double flat = 0;
  static const double raised = 1;
  static const double floating = 3;
}

abstract final class KiteStroke {
  static const double hairline = 1;
  static const double emphasis = 2;
}

abstract final class KiteOpacity {
  static const double disabled = 0.38;
  static const double secondary = 0.68;
  static const double divider = 0.55;
  static const double hover = 0.08;
  static const double pressed = 0.12;
}

abstract final class KiteMotion {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration deliberate = Duration(milliseconds: 280);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  static bool prefersReducedMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null) return mediaQuery.disableAnimations;
    return View.of(context)
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
  }

  static Duration resolve(BuildContext context, Duration duration) {
    return prefersReducedMotion(context) ? Duration.zero : duration;
  }
}

@immutable
class KiteSemanticColors extends ThemeExtension<KiteSemanticColors> {
  const KiteSemanticColors({
    required this.canvas,
    required this.navigation,
    required this.field,
    required this.selected,
    required this.unread,
    required this.mention,
    required this.danger,
  });

  final Color canvas;
  final Color navigation;
  final Color field;
  final Color selected;
  final Color unread;
  final Color mention;
  final Color danger;

  factory KiteSemanticColors.forBrightness(
    Brightness brightness,
    ColorScheme scheme, {
    bool trueBlack = false,
  }) {
    final dark = brightness == Brightness.dark;
    return KiteSemanticColors(
      canvas: trueBlack
          ? Colors.black
          : dark
          ? const Color(0xFF111513)
          : const Color(0xFFF7F8F7),
      navigation: trueBlack
          ? Colors.black
          : dark
          ? const Color(0xFF0D100F)
          : const Color(0xFFF1F3F2),
      field: trueBlack
          ? const Color(0xFF111513)
          : dark
          ? const Color(0xFF1B201E)
          : const Color(0xFFEEF1EF),
      selected: scheme.primaryContainer,
      unread: scheme.primary,
      mention: scheme.tertiary,
      danger: scheme.error,
    );
  }

  @override
  KiteSemanticColors copyWith({
    Color? canvas,
    Color? navigation,
    Color? field,
    Color? selected,
    Color? unread,
    Color? mention,
    Color? danger,
  }) {
    return KiteSemanticColors(
      canvas: canvas ?? this.canvas,
      navigation: navigation ?? this.navigation,
      field: field ?? this.field,
      selected: selected ?? this.selected,
      unread: unread ?? this.unread,
      mention: mention ?? this.mention,
      danger: danger ?? this.danger,
    );
  }

  @override
  KiteSemanticColors lerp(
    covariant ThemeExtension<KiteSemanticColors>? other,
    double t,
  ) {
    if (other is! KiteSemanticColors) return this;
    return KiteSemanticColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      navigation: Color.lerp(navigation, other.navigation, t)!,
      field: Color.lerp(field, other.field, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      unread: Color.lerp(unread, other.unread, t)!,
      mention: Color.lerp(mention, other.mention, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension KiteThemeTokens on BuildContext {
  KiteSemanticColors get kiteColors =>
      Theme.of(this).extension<KiteSemanticColors>()!;
}
