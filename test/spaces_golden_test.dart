import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/home/spaces_screen.dart';

void main() {
  for (final variant in <({String name, ThemeData theme})>[
    (name: 'light', theme: KiteTheme.light),
    (name: 'dark', theme: KiteTheme.dark),
  ]) {
    testWidgets('Spaces phone ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = SpacesController();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: RepaintBoundary(
            key: const Key('spaces-golden'),
            child: SpacesScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('spaces-golden')),
        matchesGoldenFile('goldens/spaces_phone_${variant.name}.png'),
      );
    });

    testWidgets('Spaces desktop ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = SpacesController();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: RepaintBoundary(
            key: const Key('spaces-golden'),
            child: SpacesScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('spaces-golden')),
        matchesGoldenFile('goldens/spaces_desktop_${variant.name}.png'),
      );
    });
  }
}
