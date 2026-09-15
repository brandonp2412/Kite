import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_details_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

const _roomId = '!details-settings:example.org';

void main() {
  testWidgets('room details opens injected Matrix room settings flow', (
    tester,
  ) async {
    final rooms = DeterministicRoomManagementPort();
    rooms.detailsByRoomId[_roomId] = KiteRoomDetails(
      roomId: _roomId,
      name: 'Community',
      topic: 'Topic',
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

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomDetailsScreen(
          roomId: _roomId,
          roomName: 'Community',
          management: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-settings-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-settings-screen')), findsOneWidget);
    expect(find.text('Room settings'), findsOneWidget);
    expect(
      rooms.invocations.any(
        (entry) => entry.type == RoomManagementInvocationType.details,
      ),
      isTrue,
    );
  });

  testWidgets(
    'room details omits settings action without management boundary',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoomDetailsScreen(roomId: _roomId, roomName: 'Community'),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('room-settings-button')), findsNothing);
    },
  );
}
