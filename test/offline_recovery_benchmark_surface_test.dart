import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/offline_recovery_benchmark_surface.dart';
import 'package:kite/benchmark/performance_contract.dart';

void main() {
  testWidgets('offline recovery preserves cached room geometry and ordering', (
    tester,
  ) async {
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
    expect(
      tester
          .widget<Text>(find.byKey(const Key('offline-recovery-status')))
          .data,
      'Offline cache',
    );

    const firstRoomId = '!benchmark-0000:kite.test';
    final firstRoom = find.byKey(
      const Key('offline-recovery-room-!benchmark-0000:kite.test'),
    );
    final before = tester.getTopLeft(firstRoom);
    final beforeOrder = List<String>.of(controller.cache.roomOrder.value);

    controller.recover();
    await tester.pump();

    expect(controller.isOnline.value, isTrue);
    expect(controller.cache.roomOrder.value, beforeOrder);
    expect(
      controller.cache.roomSummarySignal(firstRoomId).value?.unreadCount,
      2,
    );
    expect(tester.getTopLeft(firstRoom), before);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('offline-recovery-status')))
          .data,
      'Back online',
    );
  });
}
