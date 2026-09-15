import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
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
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['thread_open'] = <String, dynamic>{
      'journey': 'open_thread',
      'fixture': 'deterministic_thread_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'switching between thread routes stays within the frame contract',
    (tester) async {
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      final messages = timelineController.messagesFor('alice').value;
      final firstParent = messages.firstWhere(
        (message) => message.id == 'alice-98',
      );
      final secondParent = messages.firstWhere(
        (message) => message.id == 'alice-81',
      );
      final navigatorContext = tester.element(
        find.byKey(const Key('chat-panel')),
      );

      Navigator.of(navigatorContext).push(
        ThreadRoute(roomId: 'alice', parent: firstParent, reduceMotion: false),
      );
      await tester.pumpAndSettle();
      expect(find.text(firstParent.body), findsOneWidget);

      final result = await measureFrames(
        binding: binding,
        action: () async {
          Navigator.of(navigatorContext).pushReplacement(
            ThreadRoute(
              roomId: 'alice',
              parent: secondParent,
              reduceMotion: false,
            ),
          );
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: virtualizedBenchmark
            ? PerformanceContract.gateVirtualizedTotalSpan
            : PerformanceContract.gatePhysicalTotalSpan,
      );

      expect(find.text(firstParent.body), findsNothing);
      expect(find.text(secondParent.body), findsOneWidget);
      expect(find.byKey(const Key('thread-panel')), findsOneWidget);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['thread_switch'] = <String, dynamic>{
        'journey': 'switch_thread',
        'fixture': 'deterministic_thread_v1',
        'iterations': 1,
        ...result,
        'result': 'PASS',
      };
    },
  );

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
    'opening a focused thread destination stays within the frame contract',
    (tester) async {
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final destination = AppDestination.thread(
        accountId: '@alice:kite.test',
        roomId: 'alice',
        eventId: 'alice-98-thread-2',
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
        find.byKey(const Key('thread-focused-alice-98-thread-2')),
        findsOneWidget,
      );
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
