import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_details_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

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

  testWidgets('room details opens the complete member and safety flow', (
    tester,
  ) async {
    final directory = FakeRoomMemberDirectoryPort(
      members: const <RoomMember>[
        RoomMember(
          userId: '@alice:example.org',
          displayName: 'Alice',
          membership: RoomMembership.joined,
          powerLevel: 0,
        ),
      ],
    );
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@me:example.org',
      directory: directory,
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomDetailsScreen(
          roomId: _roomId,
          roomName: 'Community',
          memberManagement: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-members-management-button')));
    await tester.pumpAndSettle();

    expect(find.text('Members'), findsOneWidget);
    expect(find.byKey(const Key('member-search')), findsOneWidget);
    expect(find.byKey(const Key('room-safety-actions')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(directory.queries, <String>['']);
  });

  testWidgets(
    'room details routes report leave and forget through room lifecycle boundary',
    (tester) async {
      const member = RoomMember(
        userId: '@alice:example.org',
        displayName: 'Alice',
        membership: RoomMembership.joined,
        powerLevel: 0,
      );
      final memberMutations = FakeRoomMemberMutationPort();
      final memberManagement = RoomMemberManagementCoordinator(
        actorUserId: '@me:example.org',
        directory: FakeRoomMemberDirectoryPort(
          members: const <RoomMember>[member],
        ),
        authorization: FakeRoomMemberAuthorizationPort(),
        mutations: memberMutations,
      );
      final rooms = DeterministicRoomManagementPort();
      final directMetadata = DeterministicDirectRoomMetadataPort();
      final roomManagement = RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: directMetadata,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: RoomDetailsScreen(
            roomId: _roomId,
            roomName: 'Community',
            management: roomManagement,
            memberManagement: memberManagement,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-members-management-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-@alice:example.org')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-report')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('room-report-reason')),
        '  repeated spam  ',
      );
      await tester.tap(find.byKey(const Key('room-report-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('room-safety-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report room'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-report-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('room-safety-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('member-moderation-confirm-Leave')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('room-safety-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove local room data'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('member-moderation-confirm-Remove data')),
      );
      await tester.pumpAndSettle();

      expect(
        rooms.invocations.map((entry) => entry.type),
        <RoomManagementInvocationType>[
          RoomManagementInvocationType.reportUser,
          RoomManagementInvocationType.reportRoom,
          RoomManagementInvocationType.leaveRoom,
          RoomManagementInvocationType.forgetRoom,
        ],
      );
      expect(rooms.invocations.first.userId, member.userId);
      expect(rooms.invocations.first.reason, 'repeated spam');
      expect(memberMutations.userReports, isEmpty);
      expect(memberMutations.roomReports, isEmpty);
      expect(memberMutations.leaves, isEmpty);
      expect(memberMutations.forgottenRooms, isEmpty);
      expect(directMetadata.invocations, hasLength(2));
      expect(
        directMetadata.invocations.every((entry) => entry.userIds.isEmpty),
        isTrue,
      );
    },
  );

  testWidgets(
    'room details omits settings and managed members without boundaries',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoomDetailsScreen(roomId: _roomId, roomName: 'Community'),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('room-settings-button')), findsNothing);
      expect(
        find.byKey(const Key('room-members-management-button')),
        findsNothing,
      );
    },
  );
}
