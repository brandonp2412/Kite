import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      pollPort: DeterministicTimelinePollPort(),
    );
    selectRoom('kite');
  });

  testWidgets(
    'poll create, vote, and end preserve settled geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      timelineController.reset(
        pollPort: DeterministicTimelinePollPort(latency: Duration.zero),
      );
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final composer = find.byKey(const Key('composer'));
      final composerRect = tester.getRect(composer);

      await tester.tap(find.byKey(const Key('composer-attach')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(composer), composerRect);
      }
      await tester.tap(find.byKey(const Key('attachment-option-poll')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(composer), composerRect);
      }

      await tester.enterText(
        find.byKey(const Key('poll-question-field')),
        'Ship tonight?',
      );
      await tester.enterText(
        find.byKey(const Key('poll-option-field-0')),
        'Yes',
      );
      await tester.enterText(
        find.byKey(const Key('poll-option-field-1')),
        'Tomorrow',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('poll-create-confirm')));
      await tester.pumpAndSettle();

      final message = timelineController.messagesFor('alice').value.last;
      final card = find.byKey(Key('message-poll-${message.id}'));
      final cardRect = tester.getRect(card);
      final messageList = find.byKey(const Key('message-list'));
      final listRect = tester.getRect(messageList);

      await tester.tap(find.byKey(Key('poll-option-${message.id}-option-0')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(card), cardRect);
        expect(tester.getRect(messageList), listRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Vote recorded'), findsOneWidget);

      await tester.longPress(card);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(card), cardRect);
        expect(tester.getRect(messageList), listRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('message-action-end-poll')), findsOneWidget);
      await tester.tap(find.byKey(const Key('message-action-end-poll')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(card), cardRect);
        expect(tester.getRect(messageList), listRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Final results'), findsOneWidget);
    },
  );
}
