import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  testWidgets('cold open Alice DM has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-alice')));
        await tester.pump();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(selectedRoomId.value, 'alice');
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['open_dm_cold'] = <String, dynamic>{
      'journey': 'open_alice_dm',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('30 warm user-chat opens have zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-bob')));
    await tester.pump();

    const iterations = PerformanceContract.warmChatOpenIterations;
    final result = await measureFrames(
      binding: binding,
      action: () async {
        for (var index = 0; index < iterations; index++) {
          final target = index.isEven ? 'alice' : 'bob';
          await tester.tap(find.byKey(Key('room-$target')));
          await tester.pump();
          expect(selectedRoomId.value, target);
        }
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['open_dm_warm'] = <String, dynamic>{
      'journey': 'open_user_dm',
      'fixture': 'deterministic_v1',
      'iterations': iterations,
      ...result,
      'result': 'PASS',
    };
  });
}
