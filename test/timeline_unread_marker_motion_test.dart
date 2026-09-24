import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  test('unread marker validates and preserves a stable room signal', () {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    final messages = timelineController.messagesFor('alice').value;
    final signal = timelineController.unreadMarkerFor('alice');

    timelineController.setUnreadMarker('alice', messages.last.id);

    expect(timelineController.unreadMarkerFor('alice'), same(signal));
    expect(signal.value, messages.last.id);
    expect(
      () => timelineController.setUnreadMarker('alice', 'missing-event'),
      throwsArgumentError,
    );
  });

  test('production fully-read state positions the first unread marker', () {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    final messages = timelineController.messagesFor('alice').value;
    final fullyRead = messages[messages.length - 3];

    timelineController.applyFullyReadMarker(
      'alice',
      fullyRead.id,
      unreadMessageCount: 2,
    );
    expect(
      timelineController.unreadMarkerFor('alice').value,
      messages[messages.length - 2].id,
    );

    timelineController.applyFullyReadMarker(
      'alice',
      r'$outside-retained-window',
      unreadMessageCount: 3,
    );
    expect(
      timelineController.unreadMarkerFor('alice').value,
      messages[messages.length - 3].id,
    );

    timelineController.applyFullyReadMarker(
      'alice',
      messages.last.id,
      unreadMessageCount: 1,
    );
    expect(timelineController.unreadMarkerFor('alice').value, isNull);

    timelineController.applyFullyReadMarker(
      'alice',
      null,
      unreadMessageCount: 0,
    );
    expect(timelineController.unreadMarkerFor('alice').value, isNull);
  });

  testWidgets('unread marker overlay never changes message geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    final target = timelineController.messagesFor('alice').value.last;
    timelineController.setUnreadMarker('alice', target.id);

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('message-list'));
    final row = find.byKey(Key('message-row-${target.id}'));
    final listRect = tester.getRect(list);
    final rowRect = tester.getRect(row);
    expect(find.byKey(const Key('timeline-unread-marker')), findsOneWidget);
    expect(find.byKey(const Key('jump-to-unread')), findsOneWidget);

    timelineController.setUnreadMarker('alice', null);
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(list), listRect);
      expect(tester.getRect(row), rowRect);
      expect(tester.takeException(), isNull);
    }

    expect(find.byKey(const Key('timeline-unread-marker')), findsNothing);
  });

  testWidgets(
    'jump to unread scrolls monotonically with fixed viewport at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      final target = timelineController.messagesFor('alice').value.last;
      timelineController.setUnreadMarker('alice', target.id);

      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('message-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      final listRect = tester.getRect(list);

      await tester.drag(list, const Offset(0, 1100));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));

      var previousPixels = scrollable.position.pixels;
      await tester.tap(find.byKey(const Key('jump-to-unread')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(list), listRect);
        expect(
          scrollable.position.pixels,
          lessThanOrEqualTo(previousPixels + 0.01),
        );
        previousPixels = scrollable.position.pixels;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(Key('message-row-${target.id}')), findsOneWidget);
      expect(find.byKey(const Key('timeline-unread-marker')), findsOneWidget);
    },
  );
}
