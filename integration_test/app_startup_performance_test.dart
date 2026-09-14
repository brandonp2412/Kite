import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('app root startup composition has zero late Flutter frames', (
    tester,
  ) async {
    selectedRoomId.value = 'kite';
    KiteTheme.warmUp();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('room-list')), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['app_root_startup'] = <String, dynamic>{
      'journey': 'app_root_startup',
      'fixture': 'deterministic_kite_app_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
