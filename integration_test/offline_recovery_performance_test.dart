import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/offline_recovery_benchmark_surface.dart';
import 'package:kite/benchmark/performance_contract.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'offline recovery has zero late Flutter frames and no room jump',
    (tester) async {
      final controller = OfflineRecoveryBenchmarkController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineRecoveryBenchmarkSurface(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.cache.roomOrder.value,
        hasLength(PerformanceContract.fixtureRoomCount),
      );
      final firstRoom = find.byKey(
        const Key('offline-recovery-room-!benchmark-0000:kite.test'),
      );
      final firstRoomBefore = tester.getTopLeft(firstRoom);
      final orderBefore = List<String>.of(controller.cache.roomOrder.value);

      final result = await measureFrames(
        binding: binding,
        action: () async {
          controller.recover();
          await tester.pump();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(controller.isOnline.value, isTrue);
      expect(controller.cache.roomOrder.value, orderBefore);
      expect(tester.getTopLeft(firstRoom), firstRoomBefore);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['offline_recovery'] = <String, dynamic>{
        'journey': 'offline_recovery',
        'fixture': 'deterministic_200_cached_rooms_20_sync_updates_v1',
        'cachedRoomCount': controller.cache.roomOrder.value.length,
        'updatedRoomCount': OfflineRecoveryBenchmarkController.changedRoomCount,
        ...result,
        'result': 'PASS',
      };
    },
  );
}
