import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    selectRoom('kite');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('approved shell baseline - light', (tester) async {
    await pumpShell(tester, themeMode: ThemeMode.light);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/kite_shell_light.png'),
    );
  });

  testWidgets('approved shell baseline - dark', (tester) async {
    await pumpShell(tester, themeMode: ThemeMode.dark);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/kite_shell_dark.png'),
    );
  });
}
