import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';

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
}
