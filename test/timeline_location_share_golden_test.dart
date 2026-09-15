import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_location_share_sheet.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required ThemeMode themeMode,
    required TimelineLocationKind kind,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TimelineController(
      locationPort: DeterministicTimelineLocationPort(latency: Duration.zero),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              key: const Key('location-share-golden-surface'),
              child: ComposerLocationShareSheet(
                roomId: 'alice',
                kind: kind,
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('static location share sheet approved baseline - light', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      themeMode: ThemeMode.light,
      kind: TimelineLocationKind.staticLocation,
    );
    await expectLater(
      find.byKey(const Key('location-share-golden-surface')),
      matchesGoldenFile('goldens/location_share_light.png'),
    );
  });

  testWidgets('live location share sheet approved baseline - dark', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      themeMode: ThemeMode.dark,
      kind: TimelineLocationKind.liveLocation,
    );
    await expectLater(
      find.byKey(const Key('location-share-golden-surface')),
      matchesGoldenFile('goldens/location_share_dark.png'),
    );
  });
}
