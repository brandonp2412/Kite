import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _RecordingModerationPort implements TimelineModerationPort {
  final List<TimelineReportRequest> requests = <TimelineReportRequest>[];

  @override
  Future<void> reportMessage(TimelineReportRequest request) async {
    requests.add(request);
  }
}

class _FailingModerationPort implements TimelineModerationPort {
  @override
  Future<void> reportMessage(TimelineReportRequest request) {
    return Future<void>.error(StateError('report failed'));
  }
}

class _RecordingSharePort implements TimelineSharePort {
  final List<TimelineShareRequest> requests = <TimelineShareRequest>[];

  @override
  Future<void> shareMessage(TimelineShareRequest request) async {
    requests.add(request);
  }
}

class _ControlledSendPort implements TimelineSendPort {
  final List<Completer<TimelineSendOutcome>> attempts =
      <Completer<TimelineSendOutcome>>[];

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
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
    threadController.reset(sendPort: const DeterministicThreadSendPort());
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
      final messageBubble = find.byKey(Key('message-bubble-${message.id}'));
      final sendState = find.byKey(Key('send-state-${message.id}'));
      final sendingBubbleRect = _rectOf(tester, messageBubble);
      final sendingStateRect = _rectOf(tester, sendState);

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
      _expectSameRect(
        sendingBubbleRect,
        _rectOf(tester, messageBubble),
        'message bubble',
      );
      _expectSameRect(
        sendingStateRect,
        _rectOf(tester, sendState),
        'send-state slot',
      );
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
      _expectSameRect(
        sendingBubbleRect,
        _rectOf(tester, messageBubble),
        'message bubble',
      );
      _expectSameRect(
        sendingStateRect,
        _rectOf(tester, sendState),
        'send-state slot',
      );
      _expectSameRect(initialComposer, _rectOf(tester, composer), 'composer');
      _expectSameRect(
        initialMessageList,
        _rectOf(tester, messageList),
        'message list',
      );
    },
  );

  testWidgets(
    'message actions preserve width while reply composer expands and collapses',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final chatPanel = find.byKey(const Key('chat-panel'));
      final composer = find.byKey(const Key('composer'));
      final initialChatPanel = _rectOf(tester, chatPanel);
      final initialComposer = _rectOf(tester, composer);
      expect(initialComposer.height, 76);

      await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
      await tester.pump();
      expect(find.byKey(const Key('message-action-sheet')), findsOneWidget);

      double? previousSheetTop;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        final sheetRect = _rectOf(
          tester,
          find.byKey(const Key('message-action-sheet')),
        );
        expect(sheetRect.width, lessThanOrEqualTo(440));
        if (previousSheetTop != null) {
          expect(
            sheetRect.top,
            lessThanOrEqualTo(previousSheetTop + 0.01),
            reason: 'action sheet must move monotonically into view',
          );
        }
        previousSheetTop = sheetRect.top;
        expect(_rectOf(tester, chatPanel).width, initialChatPanel.width);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('message-action-reply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer-context')), findsOneWidget);
      expect(find.text('Replying to Alice'), findsOneWidget);
      final expandedComposer = _rectOf(tester, composer);
      expect(expandedComposer.height, 136);
      expect(expandedComposer.width, initialComposer.width);
      expect(_rectOf(tester, chatPanel).width, initialChatPanel.width);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'Reply from Kite',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pumpAndSettle();

      final reply = timelineController.messagesFor('alice').value.last;
      expect(reply.body, 'Reply from Kite');
      expect(reply.replyToMessageId, 'alice-98');
      expect(find.byKey(Key('reply-preview-${reply.id}')), findsOneWidget);
      expect(find.byKey(const Key('composer-context')), findsNothing);
      _expectSameRect(
        initialComposer,
        _rectOf(tester, composer),
        'collapsed composer',
      );
      expect(_rectOf(tester, chatPanel).width, initialChatPanel.width);
    },
  );

  testWidgets(
    'reply in thread action preserves route motion and main scroll anchor at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      threadController.reset(
        sendPort: const DeterministicThreadSendPort(latency: Duration.zero),
      );
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final target = find.byKey(const Key('message-bubble-alice-99'));
      expect(find.byKey(const Key('thread-summary-alice-99')), findsNothing);
      final scrollable = find.descendant(
        of: find.byKey(const Key('message-list')),
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable.first);
      final initialOffset = scrollState.position.pixels;

      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('message-action-reply-thread')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('message-action-reply-thread')));
      final panel = find.byKey(const Key('thread-panel'));
      for (var frame = 0; frame < 12 && panel.evaluate().isEmpty; frame++) {
        await tester.pump(PerformanceContract.motionFrame);
      }

      expect(panel, findsOneWidget);
      final panelSize = _rectOf(tester, panel).size;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, panel).size, panelSize);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('thread-composer-field')),
        'First threaded reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-composer-send')));
      await tester.pumpAndSettle();
      expect(find.text('First threaded reply'), findsOneWidget);
      expect(threadController.hasThread('alice-99'), isTrue);

      await tester.tap(find.byKey(const Key('thread-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('thread-summary-alice-99')), findsOneWidget);
      expect(scrollState.position.pixels, initialOffset);
    },
  );

  testWidgets(
    'quick reaction updates only target leaf geometry and exposes reactor detail',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final targetMessage = timelineController.messagesFor('alice').value.last;
      final target = find.byKey(const Key('message-bubble-alice-99'));
      final adjacentRow = find.byKey(const Key('message-row-alice-98'));
      final chatPanel = find.byKey(const Key('chat-panel'));
      final initialTarget = _rectOf(tester, target);
      final initialAdjacent = _rectOf(tester, adjacentRow);
      final initialChatPanel = _rectOf(tester, chatPanel);

      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-reaction-row')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-reaction-0')));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        _expectSameRect(
          initialAdjacent,
          _rectOf(tester, adjacentRow),
          'adjacent message row',
        );
        _expectSameRect(
          initialChatPanel,
          _rectOf(tester, chatPanel),
          'chat panel',
        );
        expect(tester.takeException(), isNull);
      }

      expect(_rectOf(tester, target).height, initialTarget.height);
      expect(targetMessage.reactions['👍']?.count, 1);
      expect(targetMessage.reactions['👍']?.reactedByMe, isTrue);
      final summary = find.byKey(const Key('message-reactions-alice-99'));
      expect(summary, findsOneWidget);

      await tester.tap(summary);
      await tester.pumpAndSettle();
      final details = find.byKey(const Key('reaction-details'));
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('👍 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('You')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-reaction-0')));
      await tester.pumpAndSettle();
      expect(targetMessage.reactions, isEmpty);
      expect(summary, findsNothing);
      _expectSameRect(
        initialAdjacent,
        _rectOf(tester, adjacentRow),
        'adjacent message row after toggle removal',
      );
    },
  );

  testWidgets(
    'full reaction picker transition is deterministic and preserves timeline width',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final chatPanel = find.byKey(const Key('chat-panel'));
      final initialPanel = _rectOf(tester, chatPanel);
      final target = find.byKey(const Key('message-bubble-alice-99'));

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-more-reactions')));
      await tester.pump();

      final picker = find.byKey(const Key('reaction-picker-sheet'));
      expect(picker, findsOneWidget);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, chatPanel).width, initialPanel.width);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reaction-picker-4')));
      await tester.pumpAndSettle();
      final message = timelineController.messagesFor('alice').value.last;
      expect(message.reactions['🔥']?.count, 1);
      expect(
        find.byKey(const Key('message-reactions-alice-99')),
        findsOneWidget,
      );
      expect(_rectOf(tester, chatPanel).width, initialPanel.width);
    },
  );

  testWidgets(
    'forward action keeps the source timeline anchored while sending to rooms',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final target = find.byKey(const Key('message-bubble-alice-98'));
      final anchoredLatest = find.byKey(const Key('message-row-alice-99'));
      final messageList = find.byKey(const Key('message-list'));
      final chatPanel = find.byKey(const Key('chat-panel'));
      final initialLatest = _rectOf(tester, anchoredLatest);
      final initialList = _rectOf(tester, messageList);
      final initialPanel = _rectOf(tester, chatPanel);

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-forward')));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        _expectSameRect(
          initialLatest,
          _rectOf(tester, anchoredLatest),
          'latest row',
        );
        _expectSameRect(
          initialList,
          _rectOf(tester, messageList),
          'message list',
        );
        _expectSameRect(initialPanel, _rectOf(tester, chatPanel), 'chat panel');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forward-message-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('forward-room-bob')));
      await tester.tap(find.byKey(const Key('forward-room-kite')));
      await tester.pump();
      expect(find.text('Forward to 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('forward-message-confirm')));
      await tester.pumpAndSettle();

      expect(
        timelineController.messagesFor('bob').value.last.body,
        'Deterministic message 99 in Alice',
      );
      expect(
        timelineController.messagesFor('kite').value.last.body,
        'Deterministic message 99 in Alice',
      );
      expect(find.text('Forwarded to 2 rooms'), findsOneWidget);
      _expectSameRect(
        initialLatest,
        _rectOf(tester, anchoredLatest),
        'latest row',
      );
      _expectSameRect(
        initialList,
        _rectOf(tester, messageList),
        'message list',
      );
      _expectSameRect(initialPanel, _rectOf(tester, chatPanel), 'chat panel');
    },
  );

  testWidgets('report action submits reason without moving the timeline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final moderationPort = _RecordingModerationPort();
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      moderationPort: moderationPort,
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('message-bubble-alice-98'));
    final anchoredLatest = find.byKey(const Key('message-row-alice-99'));
    final messageList = find.byKey(const Key('message-list'));
    final initialLatest = _rectOf(tester, anchoredLatest);
    final initialList = _rectOf(tester, messageList);

    await tester.longPress(target);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-report')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      _expectSameRect(
        initialLatest,
        _rectOf(tester, anchoredLatest),
        'latest row',
      );
      _expectSameRect(
        initialList,
        _rectOf(tester, messageList),
        'message list',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report-message-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-reason-1')));
    await tester.pumpAndSettle();

    expect(moderationPort.requests, hasLength(1));
    final request = moderationPort.requests.single;
    expect(request.roomId, 'alice');
    expect(request.eventId, 'alice-98');
    expect(request.reason, 'Harassment or abuse');
    expect(find.text('Report sent'), findsOneWidget);
    _expectSameRect(
      initialLatest,
      _rectOf(tester, anchoredLatest),
      'latest row',
    );
    _expectSameRect(initialList, _rectOf(tester, messageList), 'message list');
  });

  testWidgets('report failure keeps the timeline stable and offers retry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      moderationPort: _FailingModerationPort(),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final anchoredLatest = find.byKey(const Key('message-row-alice-99'));
    final messageList = find.byKey(const Key('message-list'));
    final initialLatest = _rectOf(tester, anchoredLatest);
    final initialList = _rectOf(tester, messageList);

    await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-1')));
    await tester.pumpAndSettle();

    expect(find.text('Could not send report. Try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _expectSameRect(
      initialLatest,
      _rectOf(tester, anchoredLatest),
      'latest row',
    );
    _expectSameRect(initialList, _rectOf(tester, messageList), 'message list');
  });

  testWidgets(
    'copy action preserves timeline geometry and confirms completion',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final chatPanel = find.byKey(const Key('chat-panel'));
      final messageList = find.byKey(const Key('message-list'));
      final target = find.byKey(const Key('message-bubble-alice-99'));
      final initialChatPanel = _rectOf(tester, chatPanel);
      final initialMessageList = _rectOf(tester, messageList);
      final initialTarget = _rectOf(tester, target);
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-copy')));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        _expectSameRect(
          initialChatPanel,
          _rectOf(tester, chatPanel),
          'chat panel',
        );
        _expectSameRect(
          initialMessageList,
          _rectOf(tester, messageList),
          'message list',
        );
        _expectSameRect(
          initialTarget,
          _rectOf(tester, target),
          'copied message',
        );
        expect(tester.takeException(), isNull);
      }

      await tester.pumpAndSettle();
      expect(copiedText, 'Deterministic message 100 in Alice');
      expect(find.byKey(const Key('message-action-sheet')), findsNothing);
    },
  );

  testWidgets('share action routes the exact message through the share port', (
    tester,
  ) async {
    final sharePort = _RecordingSharePort();
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      sharePort: sharePort,
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('message-bubble-alice-99'));
    final targetRect = _rectOf(tester, target);
    await tester.longPress(target);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-share')));
    await tester.pumpAndSettle();

    expect(sharePort.requests, hasLength(1));
    expect(sharePort.requests.single.roomId, 'alice');
    expect(sharePort.requests.single.eventId, 'alice-99');
    expect(
      sharePort.requests.single.body,
      'Deterministic message 100 in Alice',
    );
    expect(find.text('Share sheet opened'), findsOneWidget);
    _expectSameRect(targetRect, _rectOf(tester, target), 'shared message');
  });

  testWidgets(
    'delete confirmation redacts only the target message leaf state',
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
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final targetMessage = timelineController.messagesFor('alice').value.last;
      expect(targetMessage.id, 'alice-99');
      final target = find.byKey(const Key('message-bubble-alice-99'));
      final adjacentRow = find.byKey(const Key('message-row-alice-98'));
      final chatPanel = find.byKey(const Key('chat-panel'));
      final initialAdjacent = _rectOf(tester, adjacentRow);
      final initialChatPanel = _rectOf(tester, chatPanel);

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-message-dialog')), findsOneWidget);
      expect(targetMessage.redacted, isFalse);

      await tester.tap(find.byKey(const Key('delete-message-cancel')));
      await tester.pumpAndSettle();
      expect(targetMessage.redacted, isFalse);
      expect(find.text('Deterministic message 100 in Alice'), findsOneWidget);

      await tester.longPress(target);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-message-confirm')));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        _expectSameRect(
          initialChatPanel,
          _rectOf(tester, chatPanel),
          'chat panel',
        );
        _expectSameRect(
          initialAdjacent,
          _rectOf(tester, adjacentRow),
          'adjacent message row',
        );
        expect(tester.takeException(), isNull);
      }

      expect(targetMessage.redacted, isTrue);
      expect(targetMessage.body, isEmpty);
      expect(targetMessage.edited, isFalse);
      expect(
        find.byKey(const Key('message-redacted-alice-99')),
        findsOneWidget,
      );
      expect(find.text('Message deleted'), findsOneWidget);
      expect(find.text('Deterministic message 100 in Alice'), findsNothing);
    },
  );

  testWidgets('edit action updates only the target message leaf state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final beforeCount = timelineController.messagesFor('alice').value.length;
    final chatPanel = find.byKey(const Key('chat-panel'));
    final initialChatPanel = _rectOf(tester, chatPanel);

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-edit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('message-action-edit')));
    await tester.pumpAndSettle();

    expect(find.text('Editing message'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('composer-field')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Deterministic message 100 in Alice',
    );

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Edited message 100 in Alice',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();

    final target = timelineController.messagesFor('alice').value.last;
    expect(target.id, 'alice-99');
    expect(target.body, 'Edited message 100 in Alice');
    expect(target.edited, isTrue);
    expect(target.editHistory, <String>['Deterministic message 100 in Alice']);
    expect(timelineController.messagesFor('alice').value.length, beforeCount);
    expect(find.byKey(const Key('edited-alice-99')), findsOneWidget);
    expect(find.byKey(const Key('composer-context')), findsNothing);
    expect(_rectOf(tester, chatPanel).width, initialChatPanel.width);

    await tester.tap(find.byKey(const Key('edited-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-history-sheet')), findsOneWidget);
    expect(find.byKey(const Key('edit-history-current')), findsOneWidget);
    expect(find.byKey(const Key('edit-history-0')), findsOneWidget);
    final history = find.byKey(const Key('edit-history-sheet'));
    expect(
      find.descendant(
        of: history,
        matching: find.text('Edited message 100 in Alice'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: history,
        matching: find.text('Deterministic message 100 in Alice'),
      ),
      findsOneWidget,
    );
    expect(_rectOf(tester, chatPanel).width, initialChatPanel.width);
    expect(tester.takeException(), isNull);
  });
}
