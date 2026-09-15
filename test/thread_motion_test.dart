import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _ControlledSubscriptionPort implements ThreadSubscriptionPort {
  final List<Completer<ThreadSubscriptionOutcome>> attempts =
      <Completer<ThreadSubscriptionOutcome>>[];

  @override
  Future<ThreadSubscriptionOutcome> setFollowing({
    required String roomId,
    required String parentEventId,
    required bool following,
  }) {
    final completer = Completer<ThreadSubscriptionOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

class _ControlledThreadPort implements ThreadSendPort {
  final List<Completer<TimelineSendOutcome>> attempts =
      <Completer<TimelineSendOutcome>>[];

  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) {
    final completer = Completer<TimelineSendOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

class _FailOncePaginationPort implements ThreadPaginationPort {
  var calls = 0;

  @override
  Future<ThreadPage> loadOlder({
    required String roomId,
    required String parentEventId,
    required String? beforeReplyId,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('pagination failed');
    return ThreadPage(
      replies: <ThreadReply>[
        ThreadReply(
          id: '$parentEventId-recovered-older',
          sender: 'Alice',
          body: 'Recovered older context',
          mine: false,
          timeLabel: '09:30',
        ),
      ],
      hasMore: false,
    );
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: const DeterministicThreadSubscriptionPort(),
    );
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
    expect(
      threadController
          .unreadCountFor(
            roomId: 'alice',
            parent: timelineController
                .messagesFor('alice')
                .value
                .firstWhere((message) => message.id == 'alice-98'),
          )
          .value,
      0,
    );
    final unreadDivider = find.byKey(
      const Key('thread-unread-divider-alice-98-thread-1'),
    );
    expect(unreadDivider, findsOneWidget);
    final threadPanelRect = _rectOf(tester, panel);
    final threadComposer = find.byKey(const Key('thread-composer'));
    final threadReplyList = find.byKey(const Key('thread-reply-list'));
    final composerRect = _rectOf(tester, threadComposer);
    final replyListRect = _rectOf(tester, threadReplyList);
    final unreadDividerRect = _rectOf(tester, unreadDivider);
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
    expect(_rectOf(tester, unreadDivider), unreadDividerRect);
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

  testWidgets('thread pagination retry preserves geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final port = _FailOncePaginationPort();
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      paginationPort: port,
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('thread-panel'));
    final composer = find.byKey(const Key('thread-composer'));
    final list = find.byKey(const Key('thread-reply-list'));
    final pagination = find.byKey(const Key('thread-pagination'));
    final newestReply = find.byKey(const Key('thread-reply-alice-98-thread-2'));
    final panelRect = _rectOf(tester, panel);
    final composerRect = _rectOf(tester, composer);
    final listRect = _rectOf(tester, list);
    final paginationRect = _rectOf(tester, pagination);
    final newestReplyRect = _rectOf(tester, newestReply);

    await tester.tap(find.byKey(const Key('thread-load-older')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thread-pagination-error')), findsOneWidget);
    expect(find.text('Retry older replies'), findsOneWidget);
    expect(port.calls, 1);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, panel), panelRect);
      expect(_rectOf(tester, composer), composerRect);
      expect(_rectOf(tester, list), listRect);
      expect(_rectOf(tester, pagination), paginationRect);
      expect(_rectOf(tester, newestReply), newestReplyRect);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const Key('thread-load-older')));
    await tester.pumpAndSettle();
    expect(port.calls, 2);
    expect(find.text('Start of thread'), findsOneWidget);
    expect(find.byKey(const Key('thread-pagination-error')), findsNothing);
    expect(_rectOf(tester, panel), panelRect);
    expect(_rectOf(tester, composer), composerRect);
    expect(_rectOf(tester, list), listRect);
    expect(_rectOf(tester, pagination), paginationRect);
    expect(_rectOf(tester, newestReply), newestReplyRect);
  });

  testWidgets('thread subscription toggle preserves geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final port = _ControlledSubscriptionPort();
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: port,
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('thread-panel'));
    final header = find.byKey(const Key('thread-header'));
    final composer = find.byKey(const Key('thread-composer'));
    final list = find.byKey(const Key('thread-reply-list'));
    final toggle = find.byKey(const Key('thread-subscription-toggle'));
    final panelRect = _rectOf(tester, panel);
    final headerRect = _rectOf(tester, header);
    final composerRect = _rectOf(tester, composer);
    final listRect = _rectOf(tester, list);
    final toggleRect = _rectOf(tester, toggle);

    await tester.tap(toggle);
    await tester.pump();
    expect(
      find.byKey(const Key('thread-subscription-progress')),
      findsOneWidget,
    );
    expect(_rectOf(tester, toggle), toggleRect);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, panel), panelRect);
      expect(_rectOf(tester, header), headerRect);
      expect(_rectOf(tester, composer), composerRect);
      expect(_rectOf(tester, list), listRect);
      expect(_rectOf(tester, toggle), toggleRect);
      expect(tester.takeException(), isNull);
    }

    port.attempts.single.complete(ThreadSubscriptionOutcome.applied);
    await tester.pump();
    expect(
      find.byKey(const Key('thread-subscription-following')),
      findsOneWidget,
    );
    expect(_rectOf(tester, toggle), toggleRect);
    expect(_rectOf(tester, header), headerRect);
    expect(_rectOf(tester, composer), composerRect);
    expect(_rectOf(tester, list), listRect);

    await tester.tap(toggle);
    await tester.pump();
    port.attempts.last.complete(ThreadSubscriptionOutcome.failed);
    await tester.pump();
    expect(find.byTooltip('Retry thread notifications'), findsOneWidget);
    expect(_rectOf(tester, toggle), toggleRect);
    expect(_rectOf(tester, header), headerRect);
    expect(_rectOf(tester, composer), composerRect);
    expect(_rectOf(tester, list), listRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed thread retry preserves reply and panel geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final port = _ControlledThreadPort();
      threadController.reset(sendPort: port);
      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('thread-composer-field')),
        'Retry without reflow',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-composer-send')));
      await tester.pump();

      final reply = threadController
          .repliesFor(
            roomId: 'alice',
            parent: timelineController
                .messagesFor('alice')
                .value
                .firstWhere((message) => message.id == 'alice-98'),
          )
          .value
          .last;
      final panel = find.byKey(const Key('thread-panel'));
      final composer = find.byKey(const Key('thread-composer'));
      final list = find.byKey(const Key('thread-reply-list'));
      final row = find.byKey(Key('thread-reply-${reply.id}'));
      final panelRect = _rectOf(tester, panel);
      final composerRect = _rectOf(tester, composer);
      final listRect = _rectOf(tester, list);
      final rowRect = _rectOf(tester, row);

      port.attempts.single.complete(TimelineSendOutcome.failed);
      await tester.pump();
      expect(find.byKey(Key('thread-retry-${reply.id}')), findsOneWidget);
      expect(_rectOf(tester, row), rowRect);

      await tester.tap(find.byKey(Key('thread-retry-${reply.id}')));
      await tester.pump();
      expect(reply.sendState.value, TimelineSendState.sending);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, panel), panelRect);
        expect(_rectOf(tester, composer), composerRect);
        expect(_rectOf(tester, list), listRect);
        expect(_rectOf(tester, row), rowRect);
        expect(tester.takeException(), isNull);
      }

      port.attempts.last.complete(TimelineSendOutcome.sent);
      await tester.pump();
      expect(reply.sendState.value, TimelineSendState.sent);
      expect(_rectOf(tester, row), rowRect);
    },
  );

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
  testWidgets(
    'retargeting a mounted thread keeps focus and composer state scoped',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        paginationPort: const DeterministicThreadPaginationPort(
          latency: Duration.zero,
          pageSize: 24,
        ),
      );
      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      final firstParent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final secondParent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-81');

      Widget threadFor(TimelineMessage parent, String focusedReplyId) {
        return MaterialApp(
          theme: KiteTheme.light,
          home: ThreadView(
            key: const ValueKey<String>('retargeted-thread-view'),
            roomId: 'alice',
            parent: parent,
            focusedReplyId: focusedReplyId,
          ),
        );
      }

      await tester.pumpWidget(threadFor(firstParent, 'alice-98-thread-0'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-0')),
        findsOneWidget,
      );

      final panel = find.byKey(const Key('thread-panel'));
      final composer = find.byKey(const Key('thread-composer'));
      final list = find.byKey(const Key('thread-reply-list'));
      final panelRect = _rectOf(tester, panel);
      final composerRect = _rectOf(tester, composer);
      final listRect = _rectOf(tester, list);

      await tester.enterText(
        find.byKey(const Key('thread-composer-field')),
        'draft for the first thread',
      );
      await tester.pump();
      await tester.pumpWidget(threadFor(firstParent, 'alice-98-thread-2'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-0')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-2')),
        findsOneWidget,
      );
      expect(
        threadController
            .focusedReplyIdFor(roomId: 'alice', parent: firstParent)
            .value,
        'alice-98-thread-2',
      );
      expect(_rectOf(tester, panel), panelRect);
      expect(_rectOf(tester, composer), composerRect);
      expect(_rectOf(tester, list), listRect);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, panel), panelRect);
        expect(_rectOf(tester, composer), composerRect);
        expect(_rectOf(tester, list), listRect);
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(threadFor(secondParent, 'alice-81-thread-1'));
      await tester.pumpAndSettle();

      expect(
        threadController
            .focusedReplyIdFor(roomId: 'alice', parent: firstParent)
            .value,
        isNull,
      );
      expect(
        threadController
            .focusedReplyIdFor(roomId: 'alice', parent: secondParent)
            .value,
        'alice-81-thread-1',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('thread-composer-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.byKey(const Key('thread-focused-alice-81-thread-1')),
        findsOneWidget,
      );
      expect(_rectOf(tester, panel), panelRect);
      expect(_rectOf(tester, composer), composerRect);
      expect(_rectOf(tester, list), listRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focused thread destination stays scoped and geometry-stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        paginationPort: const DeterministicThreadPaginationPort(
          latency: Duration.zero,
          pageSize: 24,
        ),
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
      scrollState.position.jumpTo(48);
      await tester.pump();
      final anchoredOffset = scrollState.position.pixels;

      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final destination = AppDestination.thread(
        accountId: '@alice:kite.test',
        roomId: 'alice',
        eventId: 'alice-98-thread-older-0',
        threadRootEventId: 'alice-98',
      );
      final navigatorContext = tester.element(
        find.byKey(const Key('chat-panel')),
      );
      Navigator.of(navigatorContext).push(
        ThreadRoute.fromDestination(
          destination: destination,
          parent: parent,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();

      final focused = find.byKey(
        const Key('thread-focused-alice-98-thread-older-0'),
      );
      final focusedRow = find.byKey(
        const Key('thread-reply-alice-98-thread-older-0'),
      );
      final list = find.byKey(const Key('thread-reply-list'));
      expect(focused, findsOneWidget);
      expect(find.text('27 replies'), findsOneWidget);
      final focusedRect = _rectOf(tester, focusedRow);
      final listRect = _rectOf(tester, list);
      expect(focusedRect.top, greaterThanOrEqualTo(listRect.top));
      expect(focusedRect.bottom, lessThanOrEqualTo(listRect.bottom));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, focusedRow), focusedRect);
        expect(_rectOf(tester, list), listRect);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const Key('thread-back')));
      await tester.pumpAndSettle();

      expect(scrollState.position.pixels, anchoredOffset);
      expect(
        threadController
            .focusedReplyIdFor(roomId: 'alice', parent: parent)
            .value,
        isNull,
      );
      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-older-0')),
        findsNothing,
      );
    },
  );
}
