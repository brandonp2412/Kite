import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';

import 'golden_test_support.dart';

void main() {
  setUpAll(loadGoldenTestFonts);

  Future<void> renderGalleryEntry(
    WidgetTester tester, {
    required ThemeMode themeMode,
    required Size size,
    required String golden,
    KiteDarkThemeVariant darkThemeVariant = KiteDarkThemeVariant.standard,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    selectRoom('kite');
    await tester.pumpWidget(
      KiteApp(themeMode: themeMode, darkThemeVariant: darkThemeVariant),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(KiteApp), matchesGoldenFile(golden));
  }

  for (final entry in <({String name, Size size})>[
    (name: 'phone_portrait', size: Size(390, 844)),
    (name: 'phone_landscape', size: Size(844, 390)),
    (name: 'tablet', size: Size(800, 1280)),
    (name: 'desktop', size: Size(1200, 800)),
  ]) {
    for (final mode
        in <
          ({String name, ThemeMode mode, KiteDarkThemeVariant darkThemeVariant})
        >[
          (
            name: 'light',
            mode: ThemeMode.light,
            darkThemeVariant: KiteDarkThemeVariant.standard,
          ),
          (
            name: 'dark',
            mode: ThemeMode.dark,
            darkThemeVariant: KiteDarkThemeVariant.standard,
          ),
          (
            name: 'true_black',
            mode: ThemeMode.dark,
            darkThemeVariant: KiteDarkThemeVariant.trueBlack,
          ),
        ]) {
      testWidgets('gallery/home ${entry.name} ${mode.name}', (tester) async {
        await renderGalleryEntry(
          tester,
          themeMode: mode.mode,
          darkThemeVariant: mode.darkThemeVariant,
          size: entry.size,
          golden: 'goldens/home_${entry.name}_${mode.name}.png',
        );
      });
    }
  }
}
