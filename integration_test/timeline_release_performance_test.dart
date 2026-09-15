import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/benchmark/timeline_benchmark_surface.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('mixed rich timeline scroll has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      controller.messages.value,
      hasLength(PerformanceContract.timelineBenchmarkMessageCount),
    );
    expect(
      controller.messages.value.map((message) => message.kind).toSet(),
      hasLength(BenchmarkMessageKind.values.length),
    );

    final list = find.byKey(const Key('benchmark-message-list'));
    await tester.fling(list, const Offset(0, 1400), 5200);
    await tester.pumpAndSettle();
    await tester.fling(list, const Offset(0, -1400), 5200);
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.fling(list, const Offset(0, 1400), 5200);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1400), 5200);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1400), 5200);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_scroll_mixed_rich'] = <String, dynamic>{
      'journey': 'timeline_scroll_mixed_rich',
      'fixture': 'deterministic_1200_mixed_events_v1',
      'messageCount': controller.messages.value.length,
      'eventKinds': BenchmarkMessageKind.values.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('timeline pagination has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final initialCount = controller.messages.value.length;
    final list = find.byKey(const Key('benchmark-message-list'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    scrollable.position.jumpTo(216);
    await tester.pump();
    final anchoredPixels = scrollable.position.pixels;

    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.prependOlderPage();
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(
      controller.messages.value,
      hasLength(initialCount + PerformanceContract.paginationBenchmarkPageSize),
    );
    expect(scrollable.position.pixels, anchoredPixels);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_pagination'] = <String, dynamic>{
      'journey': 'timeline_pagination',
      'fixture': 'deterministic_100_older_events_v1',
      'pageSize': PerformanceContract.paginationBenchmarkPageSize,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('new-message insertion has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final initialCount = controller.messages.value.length;
    final list = find.byKey(const Key('benchmark-message-list'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    scrollable.position.jumpTo(216);
    await tester.pump();
    final anchoredPixels = scrollable.position.pixels;

    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.insertIncomingMessage();
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.messages.value, hasLength(initialCount + 1));
    expect(scrollable.position.pixels, anchoredPixels);
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(
      find.byKey(const Key('benchmark-message-incoming-timeline-message')),
      findsOneWidget,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_new_message'] = <String, dynamic>{
      'journey': 'timeline_new_message',
      'fixture': 'deterministic_incoming_event_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'reaction receipt and typing updates have zero late Flutter frames',
    (tester) async {
      final controller = TimelineBenchmarkController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
      );
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('benchmark-message-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      scrollable.position.jumpTo(216);
      await tester.pump();
      final anchoredPixels = scrollable.position.pixels;

      const iterations = 20;
      final initialReactionCount = controller.reactionCount.value;
      final initialReceiptCount = controller.readReceiptCount.value;
      final result = await measureFrames(
        binding: binding,
        action: () async {
          for (var index = 0; index < iterations; index++) {
            controller.updateEphemeralState();
            await tester.pump();
          }
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(controller.reactionCount.value, initialReactionCount + iterations);
      expect(
        controller.readReceiptCount.value,
        initialReceiptCount + iterations,
      );
      expect(controller.typing.value, isFalse);
      expect(scrollable.position.pixels, anchoredPixels);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['timeline_ephemeral_updates'] = <String, dynamic>{
        'journey': 'reaction_read_receipt_typing_update',
        'fixture': 'deterministic_ephemeral_updates_v1',
        'iterations': iterations,
        ...result,
        'result': 'PASS',
      };
    },
  );
}
