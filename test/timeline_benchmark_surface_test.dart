import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/benchmark/timeline_benchmark_surface.dart';

void main() {
  testWidgets('timeline benchmark fixture covers mixed rich event kinds', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );

    expect(
      controller.messages.value,
      hasLength(PerformanceContract.timelineBenchmarkMessageCount),
    );
    expect(
      controller.messages.value.map((message) => message.kind).toSet(),
      containsAll(BenchmarkMessageKind.values),
    );
    expect(find.byKey(const Key('benchmark-message-list')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-reactions')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-read-receipts')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-typing')), findsOneWidget);
  });

  testWidgets('timeline benchmark scrolls toward older events first', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('benchmark-message-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, 0);

    await tester.fling(
      find.byKey(const Key('benchmark-message-list')),
      const Offset(0, 1400),
      5200,
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('timeline benchmark mutations are deterministic', (tester) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );

    final initialMessageCount = controller.messages.value.length;
    controller.prependOlderPage();
    await tester.pump();
    expect(
      controller.messages.value,
      hasLength(
        initialMessageCount + PerformanceContract.paginationBenchmarkPageSize,
      ),
    );

    controller.insertIncomingMessage();
    await tester.pump();
    expect(
      find.byKey(const Key('benchmark-message-incoming-timeline-message')),
      findsOneWidget,
    );

    controller.updateEphemeralState();
    await tester.pump();
    expect(find.text('Reactions 3'), findsOneWidget);
    expect(find.text('4 read'), findsOneWidget);
    expect(find.text('Alice is typing'), findsOneWidget);
  });
}
