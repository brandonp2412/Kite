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
          initialDirectUserId: '@performance:example.org',
          onCreated: (room) => created = room,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-create-submit')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(created?.isDirect, isTrue);
    expect(
      rooms.invocations.any(
        (entry) => entry.type == RoomManagementInvocationType.create,
      ),
      isTrue,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_creation'] = <String, dynamic>{
      'journey': 'direct_room_creation_submit',
      'fixture': 'deterministic_room_management_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('room creation Space selection has zero late Flutter frames', (
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
          initialMode: RoomCreationMode.privateRoom,
          availableSpaces: const <RoomCreationSpaceOption>[
            RoomCreationSpaceOption(roomId: '!kite:example.org', name: 'Kite'),
          ],
          onCreated: (room) => created = room,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nameField = tester.widget<TextField>(
      find.byKey(const Key('room-create-name')),
    );
    nameField.controller!.text = 'Roadmap';
    await tester.pump();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final picker = find.byKey(const Key('room-create-space'));
        await tester.ensureVisible(picker);
        await tester.tap(find.text('Kite').last);
        await tester.pumpAndSettle();
        final segmented = tester.widget<SegmentedButton<String>>(picker);
        expect(segmented.selected, contains('!kite:example.org'));
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final submit = find.byKey(const Key('room-create-submit'));
    await tester.ensureVisible(submit);
    await Scrollable.ensureVisible(
      tester.element(submit),
      alignment: 0.85,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit.hitTestable());
    await tester.pumpAndSettle();

    expect(created?.isDirect, isFalse);
    expect(rooms.invocations.last.creation?.parentSpaceId, '!kite:example.org');
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_creation_space'] = <String, dynamic>{
      'journey': 'private_room_space_selection',
      'fixture': 'deterministic_room_management_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
