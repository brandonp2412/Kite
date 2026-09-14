import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';

void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: MediaViewer(items: fixture.items),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('media viewer approved baseline - light', (tester) async {
    await pumpViewer(tester, themeMode: ThemeMode.light);

    await expectLater(
      find.byType(MediaViewer),
      matchesGoldenFile('goldens/media_viewer_light.png'),
    );
  });

  testWidgets('media viewer approved baseline - dark', (tester) async {
    await pumpViewer(tester, themeMode: ThemeMode.dark);

    await expectLater(
      find.byType(MediaViewer),
      matchesGoldenFile('goldens/media_viewer_dark.png'),
    );
  });
}
