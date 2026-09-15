import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_launcher.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('warmed call chooser open has zero late Flutter frames', (
    tester,
  ) async {
    final coordinator = KiteCallCoordinator(
      gateway: DeterministicMatrixRtcGateway(),
      pictureInPicture: DeterministicPictureInPicturePort(),
      logger: StructuredLogger(
        sink: MemoryStructuredLogSink(),
        traceIds: SequenceTraceIdGenerator(seed: 920),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: Scaffold(
          appBar: AppBar(
            actions: <Widget>[
              KiteRoomCallLauncher(
                coordinator: coordinator,
                roomId: '!dm:example.org',
                roomName: 'Alice',
                isDirect: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final launcher = find.byKey(const Key('room-call-button'));
    await tester.tap(launcher);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('call-launch-sheet'))))
        .pop();
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(launcher);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('call-launch-sheet')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['call_launcher_open'] = <String, dynamic>{
      'journey': 'open_call_chooser',
      'fixture': 'deterministic_call_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
