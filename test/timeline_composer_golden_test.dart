import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  for (final variant in <({String name, ThemeData theme})>[
    (name: 'light', theme: KiteTheme.light),
    (name: 'dark', theme: KiteTheme.dark),
  ]) {
    testWidgets('timeline and composer ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-composer-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_composer_${variant.name}.png'),
      );
    });
  }
}
