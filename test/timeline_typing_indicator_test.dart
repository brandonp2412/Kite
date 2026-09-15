import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  test('typing users are deduplicated, sorted, and isolated per room', () {
    final aliceSignal = timelineController.typingUsersFor('alice');
    final bobSignal = timelineController.typingUsersFor('bob');

    timelineController.updateTypingUsers('alice', <String>[
      ' Zoe ',
      'Amy',
      'Amy',
      'You',
      '',
    ]);

    expect(timelineController.typingUsersFor('alice'), same(aliceSignal));
    expect(aliceSignal.value, <String>['Amy', 'Zoe']);
    expect(bobSignal.value, isEmpty);
  });

  testWidgets(
    'typing updates preserve timeline and composer geometry at 120 Hz',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final messageList = find.byKey(const Key('message-list'));
      final composer = find.byKey(const Key('composer'));
      final slot = find.byKey(const Key('typing-indicator-slot'));
      final messageRect = _rectOf(tester, messageList);
      final composerRect = _rectOf(tester, composer);
      final slotRect = _rectOf(tester, slot);

      timelineController.updateTypingUsers('alice', <String>['Maya', 'Sam']);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, messageList), messageRect);
        expect(_rectOf(tester, composer), composerRect);
        expect(_rectOf(tester, slot), slotRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Maya and Sam are typing…'), findsOneWidget);

      timelineController.updateTypingUsers('alice', const <String>[]);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, messageList), messageRect);
        expect(_rectOf(tester, composer), composerRect);
        expect(_rectOf(tester, slot), slotRect);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
