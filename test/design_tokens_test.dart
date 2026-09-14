import 'package:flutter/material.dart';
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
}
