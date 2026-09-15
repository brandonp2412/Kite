import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_location_card.dart';

void main() {
  Future<void> pumpLocations(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(620, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('location-golden-surface'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const <Widget>[
                    TimelineLocationCard(
                      messageId: 'static',
                      location: TimelineLocation(
                        kind: TimelineLocationKind.staticLocation,
                        latitude: -36.8485,
                        longitude: 174.7633,
                        label: 'Auckland CBD',
                      ),
                    ),
                    SizedBox(width: 20),
                    TimelineLocationCard(
                      messageId: 'live',
                      location: TimelineLocation(
                        kind: TimelineLocationKind.liveLocation,
                        latitude: -36.8468,
                        longitude: 174.7682,
                        label: 'Britomart',
                        isLiveActive: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('timeline locations approved baseline - light', (tester) async {
    await pumpLocations(tester, themeMode: ThemeMode.light);
    await expectLater(
      find.byKey(const Key('location-golden-surface')),
      matchesGoldenFile('goldens/timeline_locations_light.png'),
    );
  });

  testWidgets('timeline locations approved baseline - dark', (tester) async {
    await pumpLocations(tester, themeMode: ThemeMode.dark);
    await expectLater(
      find.byKey(const Key('location-golden-surface')),
      matchesGoldenFile('goldens/timeline_locations_dark.png'),
    );
  });
}
