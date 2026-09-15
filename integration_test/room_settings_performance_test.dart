import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_settings_screen.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

import 'performance_benchmark_harness.dart';

const _roomId = '!settings-performance:example.org';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('warmed room settings save has zero late Flutter frames', (
    tester,
  ) async {
    final rooms = DeterministicRoomManagementPort();
    rooms.detailsByRoomId[_roomId] = KiteRoomDetails(
      roomId: _roomId,
      name: 'Community',
      topic: 'Before',
      avatarUrl: null,
      canonicalAlias: '#community:example.org',
      joinRule: KiteRoomJoinRule.invite,
      encryptionEnabled: true,
      historyVisibility: KiteRoomHistoryVisibility.joined,
      notificationMode: KiteRoomNotificationMode.allMessages,
      isDirect: false,
      directUserIds: const <String>{},
    );
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    final avatarMedia = DeterministicRoomAvatarMediaPort(
      nextSelection: KiteRoomAvatarSelection(
        Uri.parse('mxc://example.org/avatar-warm'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomSettingsScreen(
          roomId: _roomId,
          coordinator: coordinator,
          avatarMedia: avatarMedia,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final avatarChoose = find.byKey(const Key('room-settings-avatar-choose'));
    await tester.tap(avatarChoose);
    await tester.pumpAndSettle();
    avatarMedia.nextSelection = KiteRoomAvatarSelection(
      Uri.parse('mxc://example.org/avatar-measured'),
    );
    final avatarResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(avatarChoose);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(avatarMedia.invocations, hasLength(2));

    final topic = tester.widget<TextField>(
      find.byKey(const Key('room-settings-topic')),
    );
    topic.controller!.text = 'Warm';
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('room-settings-form')),
      const Offset(0, -720),
    );
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('room-settings-save'));
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    topic.controller!.text = 'After';
    await tester.pump();
    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(save);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(
      rooms.invocations
          .where((entry) => entry.type == RoomManagementInvocationType.setTopic)
          .last
          .text,
      'After',
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_settings_avatar_selection'] = <String, dynamic>{
      'journey': 'room_settings_avatar_selection',
      'fixture': 'deterministic_room_avatar_media_v1',
      ...avatarResult,
      'result': 'PASS',
    };
    binding.reportData!['room_settings_save'] = <String, dynamic>{
      'journey': 'save_room_settings',
      'fixture': 'deterministic_room_management_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
