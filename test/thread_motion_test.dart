import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() {
    threadController.reset(sendPort: const DeterministicThreadSendPort());
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets('thread open and reply geometry stays deterministic at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    threadController.reset(sendPort: const DeterministicThreadSendPort());
    threadController.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 2,
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final messageList = find.byKey(const Key('message-list'));
    final scrollable = find.descendant(
      of: messageList,
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(scrollable);

    final summary = find.byKey(const Key('thread-summary-alice-98'));
    final roomRow = find.byKey(const Key('room-alice'));
    final roomUnread = find.byKey(const Key('room-thread-unread-alice'));
    expect(summary, findsOneWidget);
    expect(roomUnread, findsOneWidget);
    expect(find.byKey(const Key('thread-unread-alice-98')), findsOneWidget);
    final initialOffset = scrollState.position.pixels;
    expect(initialOffset, 0);
    final initialSummary = _rectOf(tester, summary);
    final initialMessageList = _rectOf(tester, messageList);
    final initialRoomRow = _rectOf(tester, roomRow);

    await tester.tap(summary);
    await tester.pump();
    await tester.pump(PerformanceContract.motionFrame);

    final panel = find.byKey(const Key('thread-panel'));
    expect(panel, findsOneWidget);
    final panelSize = _rectOf(tester, panel).size;
    double? previousLeft;
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      final rect = _rectOf(tester, panel);
      expect(rect.size, panelSize);
      if (previousLeft != null) {
        expect(
          rect.left,
          lessThanOrEqualTo(previousLeft + 0.01),
          reason: 'thread route must move monotonically into place',
        );
      }
      previousLeft = rect.left;
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    expect(find.text('3 replies'), findsOneWidget);
    final threadPanelRect = _rectOf(tester, panel);
    final threadComposer = find.byKey(const Key('thread-composer'));
    final threadReplyList = find.byKey(const Key('thread-reply-list'));
    final composerRect = _rectOf(tester, threadComposer);
    final replyListRect = _rectOf(tester, threadReplyList);
    final newestReply = find.byKey(const Key('thread-reply-alice-98-thread-2'));
    final newestReplyRect = _rectOf(tester, newestReply);

    await tester.tap(find.byKey(const Key('thread-load-older')));
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    expect(_rectOf(tester, newestReply), newestReplyRect);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Start of thread'), findsOneWidget);
    expect(find.text('5 replies'), findsOneWidget);
    expect(_rectOf(tester, panel), threadPanelRect);
    expect(_rectOf(tester, threadComposer), composerRect);
    expect(_rectOf(tester, threadReplyList), replyListRect);
    expect(_rectOf(tester, newestReply), newestReplyRect);

    await tester.enterText(
      find.byKey(const Key('thread-composer-field')),
      'A deterministic thread reply',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('thread-composer-send')));
    await tester.pump();

    expect(find.text('6 replies'), findsOneWidget);
    expect(find.text('A deterministic thread reply'), findsOneWidget);
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, panel), threadPanelRect);
      expect(_rectOf(tester, threadComposer), composerRect);
      expect(_rectOf(tester, threadReplyList), replyListRect);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const Key('thread-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('thread-panel')), findsNothing);
    expect(scrollState.position.pixels, initialOffset);
    expect(_rectOf(tester, messageList), initialMessageList);
    expect(_rectOf(tester, summary), initialSummary);
    expect(_rectOf(tester, roomRow), initialRoomRow);
    expect(find.text('6 replies'), findsOneWidget);
    expect(find.byKey(const Key('thread-unread-alice-98')), findsNothing);
    expect(roomUnread, findsNothing);
  });

  testWidgets('thread route preserves a nonzero main timeline scroll anchor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    threadController.reset(sendPort: const DeterministicThreadSendPort());
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final messageList = find.byKey(const Key('message-list'));
    final scrollable = find.descendant(
      of: messageList,
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(scrollable);
    scrollState.position.jumpTo(48);
    await tester.pump();
    final anchoredOffset = scrollState.position.pixels;
    expect(anchoredOffset, 48);

    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');
    final navigatorContext = tester.element(
      find.byKey(const Key('chat-panel')),
    );
    Navigator.of(navigatorContext)
        .push(ThreadRoute(roomId: 'alice', parent: parent, reduceMotion: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thread-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('thread-back')));
    await tester.pumpAndSettle();

    expect(scrollState.position.pixels, anchoredOffset);
    expect(find.byKey(const Key('thread-summary-alice-98')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
