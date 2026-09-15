import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';

import 'golden_test_support.dart';

void main() {
  setUpAll(loadGoldenTestFonts);

  const viewports = <String, Size>{
    'phone_portrait': Size(390, 844),
    'phone_landscape': Size(844, 390),
    'tablet': Size(800, 1280),
    'desktop': Size(1440, 900),
  };
  const themes = <String, ThemeMode>{
    'light': ThemeMode.light,
    'dark': ThemeMode.dark,
  };

  for (final viewport in viewports.entries) {
    for (final theme in themes.entries) {
      testWidgets('gallery home ${viewport.key} ${theme.key}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = viewport.value;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        selectRoom('kite');
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: KiteTheme.light,
            darkTheme: KiteTheme.dark,
            themeMode: theme.value,
            home: const HomeScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(HomeScreen),
          matchesGoldenFile(
            'goldens/gallery/home_${viewport.key}_${theme.key}.png',
          ),
        );
      });
    }
  }
}
