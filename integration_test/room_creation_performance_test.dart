import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_creation_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('room creation mode and submit have zero late Flutter frames', (
    tester,
  ) async {
    final rooms = DeterministicRoomManagementPort();
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    KiteCreatedRoom? created;
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomCreationScreen(
          coordinator: coordinator,
          initialMode: RoomCreationMode.directMessage,
          onCreated: (room) => created = room,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.text('Private'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('room-create-name')),
          'Performance room',
        );
        await tester.enterText(
          find.byKey(const Key('room-create-topic')),
          'Deterministic room creation benchmark',
        );
        await tester.ensureVisible(find.byKey(const Key('room-create-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('room-create-submit')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(created?.isDirect, isFalse);
    expect(
      rooms.invocations.any(
        (entry) => entry.type == RoomManagementInvocationType.create,
      ),
      isTrue,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_creation'] = <String, dynamic>{
      'journey': 'room_creation_mode_edit_submit',
      'fixture': 'deterministic_room_management_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
