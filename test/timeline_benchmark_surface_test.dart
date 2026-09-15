import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/benchmark/timeline_benchmark_surface.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

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

  testWidgets(
    'timeline benchmark mutations preserve shell geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final controller = TimelineBenchmarkController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
      );
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('benchmark-message-list'));
      final listRect = _rectOf(tester, list);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      scrollable.position.jumpTo(216);
      await tester.pump();
      final anchoredPixels = scrollable.position.pixels;
      expect(anchoredPixels, 216);

      final initialMessageCount = controller.messages.value.length;
      controller.prependOlderPage();
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), listRect);
        expect(scrollable.position.pixels, anchoredPixels);
        expect(tester.takeException(), isNull);
      }
      expect(
        controller.messages.value,
        hasLength(
          initialMessageCount + PerformanceContract.paginationBenchmarkPageSize,
        ),
      );

      controller.insertIncomingMessage();
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), listRect);
        expect(scrollable.position.pixels, anchoredPixels);
        expect(tester.takeException(), isNull);
      }
      expect(controller.messages.value, hasLength(initialMessageCount + 101));

      scrollable.position.jumpTo(0);
      await tester.pump();
      expect(
        find.byKey(const Key('benchmark-message-incoming-timeline-message')),
        findsOneWidget,
      );

      final bottomPixels = scrollable.position.pixels;
      controller.updateEphemeralState();
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), listRect);
        expect(scrollable.position.pixels, bottomPixels);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Reactions 3'), findsOneWidget);
      expect(find.text('4 read'), findsOneWidget);
      expect(find.text('Alice is typing'), findsOneWidget);
    },
  );
}
