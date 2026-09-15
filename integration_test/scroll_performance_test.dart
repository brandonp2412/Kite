import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';

const _scrollJitterEnabled = bool.fromEnvironment(
  'KITE_ARTIFICIAL_SCROLL_JITTER',
);

void _injectScrollJitter() {
  if (!_scrollJitterEnabled) return;

  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < PerformanceContract.artificialJitterDelay) {
    // Keep the UI isolate busy so the negative control must trip the same
    // frame-budget assertions as the clean benchmark.
    stopwatch.elapsedMicroseconds;
  }
}

class _ScrollJitterTrap extends StatelessWidget {
  const _ScrollJitterTrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_scrollJitterEnabled) return child;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        _injectScrollJitter();
        return false;
      },
      child: child,
    );
  }
}

Future<Map<String, dynamic>> _measureFrames({
  required IntegrationTestWidgetsFlutterBinding binding,
  required Future<void> Function() action,
  required bool enforceTotalSpan,
}) async {
  final timings = <FrameTiming>[];
  void callback(List<FrameTiming> values) => timings.addAll(values);

  await Future<void>.delayed(const Duration(milliseconds: 500));
  binding.addTimingsCallback(callback);
  await action();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  binding.removeTimingsCallback(callback);

  expect(
    timings,
    isNotEmpty,
    reason: 'The engine returned no FrameTiming samples. Run this test on a device in profile mode.',
  );

  final rawRefreshRate =
      binding.platformDispatcher.views.first.display.refreshRate;
  final refreshRate = rawRefreshRate > 0 ? rawRefreshRate : 60.0;
  final budgetUs = (1000000 / refreshRate).floor();

  final buildViolations = timings
      .where((timing) => timing.buildDuration.inMicroseconds > budgetUs)
      .length;
  final rasterViolations = timings
      .where((timing) => timing.rasterDuration.inMicroseconds > budgetUs)
      .length;
  final totalSpanViolations = timings
      .where((timing) => timing.totalSpan.inMicroseconds > budgetUs)
      .length;

  final worstBuildUs = timings
      .map((timing) => timing.buildDuration.inMicroseconds)
      .reduce((a, b) => a > b ? a : b);
  final worstRasterUs = timings
      .map((timing) => timing.rasterDuration.inMicroseconds)
      .reduce((a, b) => a > b ? a : b);
  final worstTotalSpanUs = timings
      .map((timing) => timing.totalSpan.inMicroseconds)
      .reduce((a, b) => a > b ? a : b);

  expect(
    buildViolations,
    PerformanceContract.maxBuildBudgetViolations,
    reason:
        'One or more Flutter build frames exceeded the ${budgetUs}us device frame budget. '
        'worst=${worstBuildUs}us frames=${timings.length}.',
  );
  expect(
    rasterViolations,
    PerformanceContract.maxRasterBudgetViolations,
    reason:
        'One or more Flutter raster frames exceeded the ${budgetUs}us device frame budget. '
        'worst=${worstRasterUs}us frames=${timings.length}.',
  );
  if (enforceTotalSpan) {
    expect(
      totalSpanViolations,
      PerformanceContract.maxTotalSpanBudgetViolations,
      reason:
          'One or more Flutter frames missed the end-to-end ${budgetUs}us device frame budget. '
          'worst=${worstTotalSpanUs}us frames=${timings.length}.',
    );
  }

  return <String, dynamic>{
    'refreshRateHz': refreshRate,
    'frameBudgetUs': budgetUs,
    'frames': timings.length,
    'buildBudgetViolations': buildViolations,
    'rasterBudgetViolations': rasterViolations,
    'totalSpanBudgetViolations': totalSpanViolations,
    'totalSpanGated': enforceTotalSpan,
    'worstBuildUs': worstBuildUs,
    'worstRasterUs': worstRasterUs,
    'worstTotalSpanUs': worstTotalSpanUs,
  };
}

Future<void> _dragAtFrameRate(
  WidgetTester tester,
  Finder finder,
  Offset totalOffset, {
  int steps = 30,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  final step = Offset(totalOffset.dx / steps, totalOffset.dy / steps);

  for (var index = 0; index < steps; index++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  testWidgets('room-list scrolling stays within the frame budget', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const _ScrollJitterTrap(child: KiteApp()));
    await tester.pumpAndSettle();

    final roomList = find.byKey(const Key('room-list'));
    expect(roomList, findsOneWidget);

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await _dragAtFrameRate(tester, roomList, const Offset(0, -600));
        await _dragAtFrameRate(tester, roomList, const Offset(0, 600));
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['scroll_room_list'] = <String, dynamic>{
      'journey': 'scroll_room_list',
      'fixture': 'deterministic_v1',
      'rooms': PerformanceContract.fixtureRoomCount,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('timeline scrolling stays within the frame budget', (
    tester,
  ) async {
    selectRoom('alice');
    await tester.pumpWidget(const _ScrollJitterTrap(child: KiteApp()));
    await tester.pumpAndSettle();

    final messageList = find.byKey(const Key('message-list'));
    expect(messageList, findsOneWidget);

    // Warm the existing deterministic timeline once before measuring steady-state
    // scrolling, matching the already-warm room list and avoiding first-use
    // software-renderer shader/glyph setup contaminating the scroll journey.
    await _dragAtFrameRate(tester, messageList, const Offset(0, -600));
    await _dragAtFrameRate(tester, messageList, const Offset(0, 600));

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await _dragAtFrameRate(tester, messageList, const Offset(0, -600));
        await _dragAtFrameRate(tester, messageList, const Offset(0, 600));
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['scroll_timeline'] = <String, dynamic>{
      'journey': 'scroll_timeline',
      'fixture': 'deterministic_v1',
      'messages': PerformanceContract.fixtureMessagesPerRoom,
      ...result,
      'result': 'PASS',
    };
  });
}
