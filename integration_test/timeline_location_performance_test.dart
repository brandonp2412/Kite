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

  testWidgets('live location state update has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    final live = TimelineMessage(
      id: 'benchmark-live-location',
      sender: 'Alice',
      body: '',
      mine: false,
      timeLabel: 'now',
      location: const TimelineLocation(
        kind: TimelineLocationKind.liveLocation,
        latitude: -36.8468,
        longitude: 174.7682,
        label: 'Britomart',
        isLiveActive: true,
      ),
    );
    final messages = timelineController.messagesFor('alice');
    messages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...messages.value,
      live,
    ]);
    selectRoom('alice');

    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('message-location-benchmark-live-location')),
      findsOneWidget,
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        timelineController.updateLocation(
          'alice',
          live.id,
          live.location!.copyWith(isLiveActive: false),
        );
        await tester.pump();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('Live location ended'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['live_location_update'] = <String, dynamic>{
      'journey': 'live_location_state_update',
      'fixture': 'deterministic_location_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
