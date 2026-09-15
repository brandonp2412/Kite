import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/spaces_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() => spacesController.reset());

  testWidgets(
    'Spaces route and join state preserve deterministic geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      spacesController.reset();
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-spaces')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-spaces')));
      await tester.pump();
      await tester.pump(PerformanceContract.motionFrame);
      final screen = find.byKey(const Key('spaces-screen'));
      expect(screen, findsOneWidget);
      final screenSize = _rectOf(tester, screen).size;
      double? previousLeft;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        final rect = _rectOf(tester, screen);
        expect(rect.size, screenSize);
        if (previousLeft != null) {
          expect(rect.left, lessThanOrEqualTo(previousLeft + 0.01));
        }
        previousLeft = rect.left;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('spaces-header'));
      final headerRect = _rectOf(tester, header);
      await tester.tap(find.byKey(const Key('spaces-chip-people-space')));
      await tester.pump();
      expect(_rectOf(tester, header), headerRect);
      expect(find.byKey(const Key('space-body-people-space')), findsOneWidget);

      final slot = find.byKey(const Key('space-room-action-slot-coffee-club'));
      final row = find.byKey(const Key('space-room-row-coffee-club'));
      final slotRect = _rectOf(tester, slot);
      final rowRect = _rectOf(tester, row);
      await tester.tap(find.byKey(const Key('space-room-join-coffee-club')));
      await tester.pump();
      expect(_rectOf(tester, slot), slotRect);
      expect(_rectOf(tester, row), rowRect);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, slot), slotRect);
        expect(_rectOf(tester, row), rowRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(_rectOf(tester, slot), slotRect);
      expect(_rectOf(tester, row), rowRect);
      expect(
        spacesController.joinStateFor('coffee-club').value,
        SpaceRoomJoinState.joined,
      );
    },
  );
}
