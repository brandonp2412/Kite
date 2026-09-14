import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _ControlledSendPort implements TimelineSendPort {
  final List<Completer<TimelineSendOutcome>> attempts =
      <Completer<TimelineSendOutcome>>[];

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    final completer = Completer<TimelineSendOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void _expectSameRect(Rect expected, Rect actual, String label) {
  expect(
    actual,
    expected,
    reason:
        '$label moved during the send interaction: expected $expected, got $actual',
  );
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets(
    'send failure is deterministic and retryable without panel reflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final sendPort = _ControlledSendPort();
      timelineController.reset(sendPort: sendPort);
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final chatPanel = find.byKey(const Key('chat-panel'));
      final composer = find.byKey(const Key('composer'));
      final messageList = find.byKey(const Key('message-list'));
      final initialChatPanel = _rectOf(tester, chatPanel);
      final initialComposer = _rectOf(tester, composer);
      final initialMessageList = _rectOf(tester, messageList);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'Message from Kite',
      );
      await tester.pump();
      expect(find.byKey(const Key('composer-send')), findsOneWidget);

      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pump();

      expect(sendPort.attempts, hasLength(1));
      final message = timelineController.messagesFor('alice').value.last;
      expect(message.body, 'Message from Kite');
      expect(message.sendState.value, TimelineSendState.sending);
      expect(find.text('Message from Kite'), findsOneWidget);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        _expectSameRect(
          initialChatPanel,
          _rectOf(tester, chatPanel),
          'chat panel',
        );
        _expectSameRect(initialComposer, _rectOf(tester, composer), 'composer');
        _expectSameRect(
          initialMessageList,
          _rectOf(tester, messageList),
          'message list',
        );
        expect(tester.takeException(), isNull);
      }

      sendPort.attempts.single.complete(TimelineSendOutcome.failed);
      await tester.pump();
      expect(message.sendState.value, TimelineSendState.failed);
      expect(find.byKey(Key('retry-${message.id}')), findsOneWidget);
      _expectSameRect(initialComposer, _rectOf(tester, composer), 'composer');
      _expectSameRect(
        initialMessageList,
        _rectOf(tester, messageList),
        'message list',
      );

      await tester.tap(find.byKey(Key('retry-${message.id}')));
      await tester.pump();
      expect(sendPort.attempts, hasLength(2));
      expect(message.sendState.value, TimelineSendState.sending);

      sendPort.attempts.last.complete(TimelineSendOutcome.sent);
      await tester.pump();
      expect(message.sendState.value, TimelineSendState.sent);
      expect(find.byIcon(Icons.done_rounded), findsWidgets);
      _expectSameRect(initialComposer, _rectOf(tester, composer), 'composer');
      _expectSameRect(
        initialMessageList,
        _rectOf(tester, messageList),
        'message list',
      );
    },
  );
}
