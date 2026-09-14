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
    threadController.reset(sendPort: const DeterministicThreadSendPort());
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
