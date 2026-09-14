import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';

void main() {
  test('Kite themes install semantic colour tokens', () {
    final light = KiteTheme.light.extension<KiteSemanticColors>();
    final dark = KiteTheme.dark.extension<KiteSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.canvas, isNot(dark!.canvas));
    expect(light.selected, KiteTheme.light.colorScheme.primaryContainer);
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

    final lightBars = KiteSystemBars.forTheme(KiteTheme.light);
    expect(lightBars.statusBarIconBrightness, Brightness.dark);
    expect(lightBars.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('KiteApp applies true-black theme and matching system bars', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const KiteApp(
        themeMode: ThemeMode.dark,
        darkThemeVariant: KiteDarkThemeVariant.trueBlack,
      ),
    );
    await tester.pumpAndSettle();

    final compactHome = tester.element(find.byKey(const Key('compact-home')));
    expect(Theme.of(compactHome).scaffoldBackgroundColor, Colors.black);

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
