import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

class _FailOnceThreadPort implements ThreadSendPort {
  final Set<String> _failed = <String>{};

  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) async {
    if (_failed.add(transactionId)) return TimelineSendOutcome.failed;
    return TimelineSendOutcome.sent;
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
    if (calls == 1) throw StateError('thread pagination failed');
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  setUp(() {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: const DeterministicThreadSubscriptionPort(),
    );
    threadController.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 2,
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
  });

  testWidgets('opening a thread stays within the frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('thread-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('thread-unread-divider-alice-98-thread-1')),
      findsOneWidget,
    );
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');
    expect(
      threadController.unreadCountFor(roomId: 'alice', parent: parent).value,
      0,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_open'] = <String, dynamic>{
      'journey': 'open_thread',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('loading older thread replies stays within the frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('thread-load-older')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(
      threadController.repliesFor(roomId: 'alice', parent: parent).value,
      hasLength(5),
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_pagination'] = <String, dynamic>{
      'journey': 'paginate_thread',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'retrying failed thread pagination stays within the frame contract',
    (tester) async {
      final port = _FailOncePaginationPort();
      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        paginationPort: port,
      );
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');

      await tester.tap(find.byKey(const Key('thread-load-older')));
      await tester.pumpAndSettle();
      expect(port.calls, 1);
      expect(find.byKey(const Key('thread-pagination-error')), findsOneWidget);

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(find.byKey(const Key('thread-load-older')));
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: virtualizedBenchmark
            ? PerformanceContract.gateVirtualizedTotalSpan
            : PerformanceContract.gatePhysicalTotalSpan,
      );

      expect(port.calls, 2);
      expect(
        threadController.repliesFor(roomId: 'alice', parent: parent).value,
        hasLength(4),
      );
      expect(find.text('Start of thread'), findsOneWidget);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['thread_pagination_retry'] = <String, dynamic>{
        'journey': 'retry_thread_pagination',
        'fixture': 'deterministic_thread_v1',
        'iterations': 1,
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets(
    'retrying a failed thread reply stays within the frame contract',
    (tester) async {
      threadController.reset(sendPort: _FailOnceThreadPort());
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final reply = threadController.sendReply(
        roomId: 'alice',
        parent: parent,
        rawBody: 'Profile-mode retry thread reply',
      );
      await tester.pumpAndSettle();
      expect(reply.sendState.value, TimelineSendState.failed);

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(find.byKey(Key('thread-retry-${reply.id}')));
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: virtualizedBenchmark
            ? PerformanceContract.gateVirtualizedTotalSpan
            : PerformanceContract.gatePhysicalTotalSpan,
      );

      expect(reply.sendState.value, TimelineSendState.sent);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['thread_reply_retry'] = <String, dynamic>{
        'journey': 'retry_thread_reply',
        'fixture': 'deterministic_thread_v1',
        'iterations': 1,
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets('toggling thread notifications stays within the frame contract', (
    tester,
  ) async {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: const DeterministicThreadSubscriptionPort(
        latency: Duration.zero,
      ),
    );
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('thread-subscription-toggle')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(
      threadController.isFollowingFor(roomId: 'alice', parent: parent).value,
      isTrue,
    );
    expect(
      find.byKey(const Key('thread-subscription-following')),
      findsOneWidget,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_subscription_toggle'] = <String, dynamic>{
      'journey': 'toggle_thread_notifications',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('sending a thread reply stays within the frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');

    final result = await measureFrames(
      binding: binding,
      action: () async {
        threadController.sendReply(
          roomId: 'alice',
          parent: parent,
          rawBody: 'Profile-mode thread reply',
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(
      threadController.repliesFor(roomId: 'alice', parent: parent).value,
      hasLength(4),
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_reply_send'] = <String, dynamic>{
      'journey': 'send_thread_reply',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
  testWidgets('thread attachment preview and send stay within frame contract', (
    tester,
  ) async {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(latency: Duration.zero),
      attachmentSendPort: const DeterministicThreadAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('thread-composer-attach')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('attachment-option-photo-library')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('thread-attachment-preview')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('thread-composer-field')),
          'Profile-mode thread media',
        );
        await tester.tap(find.byKey(const Key('thread-composer-send')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final reply = threadController
        .repliesFor(roomId: 'alice', parent: parent)
        .value
        .last;
    expect(reply.attachment?.id, 'photo-library');
    expect(reply.sendState.value, TimelineSendState.sent);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_attachment_send'] = <String, dynamic>{
      'journey': 'thread_attachment_preview_send',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('opening the thread list stays within the frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-threads-action')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('thread-list-panel')), findsOneWidget);
    expect(find.byKey(const Key('thread-list-row-alice-98')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_list_open'] = <String, dynamic>{
      'journey': 'open_thread_list',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('paging the thread list stays within the frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-threads-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thread-list-row-alice-30')), findsNothing);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('thread-list-load-more')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('thread-list-row-alice-30')), findsOneWidget);
    expect(find.byKey(const Key('thread-list-load-more')), findsNothing);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_list_paging'] = <String, dynamic>{
      'journey': 'page_thread_list',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('opening thread media stays within the frame contract', (
    tester,
  ) async {
    final parent = timelineController
        .messagesFor('alice')
        .value
        .firstWhere((message) => message.id == 'alice-98');
    final seededReplies = threadController
        .repliesFor(roomId: 'alice', parent: parent)
        .value;
    threadController.applyThreadSnapshot(
      roomId: 'alice',
      parent: parent,
      replies: <ThreadReply>[
        seededReplies[0],
        seededReplies[1],
        ThreadReply(
          id: 'alice-98-thread-2',
          sender: 'Alice',
          body: 'Done — the latest update is ready to review.',
          mine: false,
          timeLabel: '10:24',
          attachment: const TimelineAttachment(
            id: 'thread-review-image',
            kind: TimelineAttachmentKind.image,
            name: 'review.png',
            sizeLabel: '1.8 MB · Photo',
          ),
        ),
      ],
      hasMore: true,
      unreadCount: 2,
      latestReadReplyId: seededReplies.first.id,
    );
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(
            const Key('message-attachment-open-thread-alice-98-thread-2'),
          ),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('media-viewer')), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_media_open'] = <String, dynamic>{
      'journey': 'open_thread_media',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'retargeting a mounted thread focus stays within the frame contract',
    (tester) async {
      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        paginationPort: const DeterministicThreadPaginationPort(
          latency: Duration.zero,
        ),
      );
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');

      Widget threadFor(String focusedReplyId) {
        return MaterialApp(
          theme: KiteTheme.dark,
          home: ThreadView(
            key: const ValueKey<String>('retargeted-thread-view'),
            roomId: 'alice',
            parent: parent,
            focusedReplyId: focusedReplyId,
          ),
        );
      }

      await tester.pumpWidget(threadFor('alice-98-thread-0'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-0')),
        findsOneWidget,
      );

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.pumpWidget(threadFor('alice-98-thread-2'));
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: virtualizedBenchmark
            ? PerformanceContract.gateVirtualizedTotalSpan
            : PerformanceContract.gatePhysicalTotalSpan,
      );

      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-0')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-2')),
        findsOneWidget,
      );
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['thread_focus_retarget'] = <String, dynamic>{
        'journey': 'retarget_thread_focus',
        'fixture': 'deterministic_thread_v1',
        'iterations': 1,
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets(
    'opening a focused thread destination stays within the frame contract',
    (tester) async {
      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        paginationPort: const DeterministicThreadPaginationPort(
          latency: Duration.zero,
          pageSize: 24,
        ),
      );
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
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

      final result = await measureFrames(
        binding: binding,
        action: () async {
          Navigator.of(navigatorContext).push(
            ThreadRoute.fromDestination(
              destination: destination,
              parent: parent,
              reduceMotion: false,
            ),
          );
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: virtualizedBenchmark
            ? PerformanceContract.gateVirtualizedTotalSpan
            : PerformanceContract.gatePhysicalTotalSpan,
      );

      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-older-0')),
        findsOneWidget,
      );
      expect(find.text('27 replies'), findsOneWidget);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['thread_focus_open'] = <String, dynamic>{
        'journey': 'open_focused_thread_reply',
        'fixture': 'deterministic_thread_v1',
        'iterations': 1,
        ...result,
        'result': 'PASS',
      };
    },
  );
}
