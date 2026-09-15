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
    final black = KiteTheme.black.extension<KiteSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(black, isNotNull);
    expect(light!.canvas, isNot(dark!.canvas));
    expect(black!.canvas, Colors.black);
    expect(black.navigation, Colors.black);
    expect(light.selected, KiteTheme.light.colorScheme.primaryContainer);
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
