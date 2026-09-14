import 'dart:async';

import 'package:kite/benchmark/performance_contract.dart';

abstract final class BenchmarkJitterInjector {
  static const enabled = bool.fromEnvironment('KITE_ARTIFICIAL_JITTER');
  static const delay = PerformanceContract.artificialJitterDelay;

  static void injectBuildDelay() {
    if (!enabled) return;

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < delay) {
      Zone.current.hashCode;
    }
  }
}
