import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';

Future<Map<String, dynamic>> measureFrames({
  required IntegrationTestWidgetsFlutterBinding binding,
  required Future<void> Function() action,
  required bool enforceTotalSpan,
}) async {
  final timings = <FrameTiming>[];
  void callback(List<FrameTiming> values) => timings.addAll(values);

  await Future<void>.delayed(const Duration(seconds: 2));
  binding.addTimingsCallback(callback);
  await action();
  await Future<void>.delayed(const Duration(seconds: 2));
  binding.removeTimingsCallback(callback);

  expect(
    timings,
    isNotEmpty,
    reason: 'The engine returned no FrameTiming samples. Run this test on a real device in profile mode.',
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

  int worstBuildUs = 0;
  int worstRasterUs = 0;
  int worstTotalSpanUs = 0;
  for (final timing in timings) {
    if (timing.buildDuration.inMicroseconds > worstBuildUs) {
      worstBuildUs = timing.buildDuration.inMicroseconds;
    }
    if (timing.rasterDuration.inMicroseconds > worstRasterUs) {
      worstRasterUs = timing.rasterDuration.inMicroseconds;
    }
    if (timing.totalSpan.inMicroseconds > worstTotalSpanUs) {
      worstTotalSpanUs = timing.totalSpan.inMicroseconds;
    }
  }

  final result = <String, dynamic>{
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
    'framesRaw': <Map<String, int>>[
      for (final timing in timings)
        <String, int>{
          'buildUs': timing.buildDuration.inMicroseconds,
          'rasterUs': timing.rasterDuration.inMicroseconds,
          'totalSpanUs': timing.totalSpan.inMicroseconds,
        },
    ],
  };

  debugPrint(
    'KITE_PERF frames=${timings.length} budgetUs=$budgetUs '
    'buildViolations=$buildViolations rasterViolations=$rasterViolations '
    'totalSpanViolations=$totalSpanViolations worstBuildUs=$worstBuildUs '
    'worstRasterUs=$worstRasterUs worstTotalSpanUs=$worstTotalSpanUs',
  );
  for (var index = 0; index < timings.length; index++) {
    final timing = timings[index];
    if (timing.buildDuration.inMicroseconds > budgetUs ||
        timing.rasterDuration.inMicroseconds > budgetUs ||
        (enforceTotalSpan && timing.totalSpan.inMicroseconds > budgetUs)) {
      debugPrint(
        'KITE_PERF_VIOLATION frame=$index '
        'buildUs=${timing.buildDuration.inMicroseconds} '
        'rasterUs=${timing.rasterDuration.inMicroseconds} '
        'totalSpanUs=${timing.totalSpan.inMicroseconds}',
      );
    }
  }

  expect(
    buildViolations,
    PerformanceContract.maxBuildBudgetViolations,
    reason:
        'One or more Flutter build frames exceeded the ${budgetUs}us device frame budget.',
  );
  expect(
    rasterViolations,
    PerformanceContract.maxRasterBudgetViolations,
    reason:
        'One or more Flutter raster frames exceeded the ${budgetUs}us device frame budget.',
  );
  if (enforceTotalSpan) {
    expect(
      totalSpanViolations,
      PerformanceContract.maxTotalSpanBudgetViolations,
      reason:
          'One or more Flutter frames missed the end-to-end ${budgetUs}us device frame budget.',
    );
  }

  return result;
}
