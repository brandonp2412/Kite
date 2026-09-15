import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/home/home_screen.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void _expectContrast(
  Color foreground,
  Color background,
  double minimum, {
  required String reason,
}) {
  expect(
    _contrastRatio(foreground, background),
    greaterThanOrEqualTo(minimum),
    reason: reason,
  );
}

void main() {
  test('Kite themes install semantic colour tokens', () {
    final light = KiteTheme.light.extension<KiteSemanticColors>();
    final dark = KiteTheme.dark.extension<KiteSemanticColors>();
    final black = KiteTheme.black.extension<KiteSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(black, isNotNull);
    expect(light!.canvas, isNot(dark!.canvas));
    expect(black!.canvas, Colors.black);
    expect(black.navigation, Colors.black);
    expect(light.selected, KiteTheme.light.colorScheme.primaryContainer);
  });

  test('semantic colour pairs meet WCAG text and UI contrast floors', () {
    final themes = <String, ThemeData>{
      'light': KiteTheme.light,
      'dark': KiteTheme.dark,
      'black': KiteTheme.black,
    };

    for (final entry in themes.entries) {
      final scheme = entry.value.colorScheme;
      final tokens = entry.value.extension<KiteSemanticColors>()!;
      _expectContrast(
        scheme.onSurface,
        tokens.canvas,
        4.5,
        reason: '${entry.key} primary text on canvas',
      );
      _expectContrast(
        scheme.onSurfaceVariant,
        tokens.field,
        4.5,
        reason: '${entry.key} secondary text on field',
      );
      _expectContrast(
        scheme.onPrimaryContainer,
        tokens.selected,
        4.5,
        reason: '${entry.key} selected-state content',
      );
      _expectContrast(
        tokens.unread,
        tokens.canvas,
        3,
        reason: '${entry.key} unread indicator against canvas',
      );
      _expectContrast(
        tokens.mention,
        tokens.canvas,
        3,
        reason: '${entry.key} mention indicator against canvas',
      );
      _expectContrast(
        tokens.danger,
        tokens.canvas,
        3,
        reason: '${entry.key} destructive indicator against canvas',
      );
    }
  });

  testWidgets('true-black app applies dark system bars on black surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(trueBlack: true));
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byKey(const Key('sidebar')));
    expect(Theme.of(homeContext).scaffoldBackgroundColor, Colors.black);

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const Key('kite-system-bars')),
    );
    expect(region.value.systemNavigationBarColor, Colors.black);
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.systemNavigationBarIconBrightness, Brightness.light);
  });

  testWidgets('motion duration collapses when reduced motion is requested', (
    tester,
  ) async {
    Duration? resolved;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            resolved = KiteMotion.resolve(context, KiteMotion.deliberate);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, Duration.zero);
  });

  testWidgets('KiteApp removes theme motion when reduced motion is requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: KiteApp(themeMode: ThemeMode.light),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeAnimationDuration, Duration.zero);
  });

  testWidgets('motion duration is retained under normal motion settings', (
    tester,
  ) async {
    Duration? resolved;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            resolved = KiteMotion.resolve(context, KiteMotion.deliberate);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, KiteMotion.deliberate);
  });

  test(
    'component overlay surfaces use the shared shape and elevation tokens',
    () {
      for (final theme in <ThemeData>[
        KiteTheme.light,
        KiteTheme.dark,
        KiteTheme.black,
      ]) {
        final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
        final dialogRadius = dialogShape.borderRadius as BorderRadius;
        expect(dialogRadius.topLeft.x, KiteRadii.lg);
        expect(theme.dialogTheme.elevation, KiteElevation.overlay);

        final sheetShape =
            theme.bottomSheetTheme.shape as RoundedRectangleBorder;
        final sheetRadius = sheetShape.borderRadius as BorderRadius;
        expect(sheetRadius.topLeft.x, KiteRadii.lg);
        expect(sheetRadius.bottomLeft.x, 0);
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(theme.bottomSheetTheme.modalElevation, KiteElevation.overlay);

        final popupShape = theme.popupMenuTheme.shape as RoundedRectangleBorder;
        final popupRadius = popupShape.borderRadius as BorderRadius;
        expect(popupRadius.topLeft.x, KiteRadii.md);
        expect(theme.popupMenuTheme.elevation, KiteElevation.overlay);

        final menuShape = theme.menuTheme.style?.shape?.resolve({});
        expect(menuShape, isA<RoundedRectangleBorder>());
        expect(
          ((menuShape! as RoundedRectangleBorder).borderRadius as BorderRadius)
              .topLeft
              .x,
          KiteRadii.md,
        );
        expect(
          theme.menuTheme.style?.elevation?.resolve({}),
          KiteElevation.overlay,
        );

        final snackShape = theme.snackBarTheme.shape as RoundedRectangleBorder;
        final snackRadius = snackShape.borderRadius as BorderRadius;
        expect(snackRadius.topLeft.x, KiteRadii.sm);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.snackBarTheme.elevation, KiteElevation.floating);

        final tooltipDecoration =
            theme.tooltipTheme.decoration as BoxDecoration;
        final tooltipRadius = tooltipDecoration.borderRadius as BorderRadius;
        expect(tooltipRadius.topLeft.x, KiteRadii.sm);
      }
    },
  );

  test('theme foreground pairs meet WCAG AA normal-text contrast', () {
    for (final theme in <ThemeData>[
      KiteTheme.light,
      KiteTheme.dark,
      KiteTheme.black,
    ]) {
      final scheme = theme.colorScheme;
      for (final pair in <(Color, Color)>[
        (scheme.onSurface, scheme.surface),
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onSecondaryContainer, scheme.secondaryContainer),
        (scheme.onError, scheme.error),
        (scheme.onErrorContainer, scheme.errorContainer),
      ]) {
        expect(
          _contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason:
              '${pair.$1} on ${pair.$2} in ${theme.brightness} theme '
              'must meet WCAG AA normal-text contrast',
        );
      }
    }
  });

  test('true-black theme and system bars use deliberate black surfaces', () {
    final theme = KiteTheme.black;
    final bars = KiteSystemBars.forTheme(theme);

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.surface, Colors.black);
    expect(theme.navigationRailTheme.backgroundColor, Colors.black);
    expect(bars.statusBarColor, Colors.transparent);
    expect(bars.statusBarIconBrightness, Brightness.light);
    expect(bars.systemNavigationBarColor, Colors.black);
    expect(bars.systemNavigationBarIconBrightness, Brightness.light);

    final darkBars = KiteSystemBars.forTheme(KiteTheme.dark);
    expect(darkBars.statusBarIconBrightness, Brightness.light);
    expect(
      darkBars.systemNavigationBarColor,
      KiteTheme.dark.scaffoldBackgroundColor,
    );
    expect(darkBars.systemNavigationBarIconBrightness, Brightness.light);

    final lightBars = KiteSystemBars.forTheme(KiteTheme.light);
    expect(lightBars.statusBarIconBrightness, Brightness.dark);
    expect(
      lightBars.systemNavigationBarColor,
      KiteTheme.light.scaffoldBackgroundColor,
    );
    expect(lightBars.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('KiteApp applies true-black theme and matching system bars', (
    tester,
  ) async {
    selectRoom('kite');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const KiteApp(
        themeMode: ThemeMode.dark,
        darkThemeVariant: KiteDarkThemeVariant.trueBlack,
      ),
    );
    await tester.pumpAndSettle();

    final home = tester.element(find.byType(HomeScreen));
    expect(Theme.of(home).scaffoldBackgroundColor, Colors.black);

    final annotatedRegion = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        );
    expect(annotatedRegion.value.systemNavigationBarColor, Colors.black);
    expect(
      annotatedRegion.value.systemNavigationBarIconBrightness,
      Brightness.light,
    );
  });

  testWidgets('KiteApp removes route motion when the platform requests it', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    selectRoom('kite');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final navigatorContext = tester.element(find.byType(Navigator));
    expect(
      Theme.of(navigatorContext).pageTransitionsTheme,
      KiteMotion.reducedPageTransitions,
    );
  });

  testWidgets('motion durations collapse when reduced motion is requested', (
    tester,
  ) async {
    late BuildContext normalContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            normalContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(KiteMotion.reducedMotion(normalContext), isFalse);
    expect(
      KiteMotion.duration(normalContext, KiteMotion.standard),
      KiteMotion.standard,
    );
    expect(
      KiteMotion.pageTransitions(
        normalContext,
        KiteTheme.light.pageTransitionsTheme,
      ),
      KiteTheme.light.pageTransitionsTheme,
    );

    late BuildContext reducedContext;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              reducedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(KiteMotion.reducedMotion(reducedContext), isTrue);
    expect(
      KiteMotion.duration(reducedContext, KiteMotion.emphasized),
      Duration.zero,
    );
    expect(
      KiteMotion.pageTransitions(
        reducedContext,
        KiteTheme.light.pageTransitionsTheme,
      ),
      KiteMotion.reducedPageTransitions,
    );

    late BuildContext accessibleNavigationContext;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              accessibleNavigationContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(KiteMotion.reducedMotion(accessibleNavigationContext), isTrue);
    expect(
      KiteMotion.duration(accessibleNavigationContext, KiteMotion.fast),
      Duration.zero,
    );
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
