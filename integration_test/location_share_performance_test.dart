import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      locationPort: DeterministicTimelineLocationPort(),
    );
    selectRoom('kite');
  });

  testWidgets('location share and stop stay within the frame contract', (
    tester,
  ) async {
    timelineController.reset(
      locationPort: DeterministicTimelineLocationPort(latency: Duration.zero),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-attach')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('attachment-option-live-location')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('location-share-confirm')));
        await tester.pumpAndSettle();
        final message = timelineController.messagesFor('alice').value.last;
        await tester.tap(
          find.byKey(Key('message-location-stop-${message.id}')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.location?.kind, TimelineLocationKind.liveLocation);
    expect(message.location?.isLiveActive, isFalse);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['location_share'] = <String, dynamic>{
      'journey': 'attachment_location_share_and_stop',
      'fixture': 'deterministic_location_share_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
