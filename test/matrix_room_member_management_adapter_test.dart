import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/matrix_room_member_management_adapter.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  test(
    'Matrix member adapter maps and filters the production directory',
    () async {
      final port = MatrixRoomMemberManagementPort(
        loadMembers: (_) async => const <MatrixSdkRoomMember>[
          MatrixSdkRoomMember(
            userId: '@alice:example.org',
            displayName: 'Alice',
            powerLevel: 100,
          ),
          MatrixSdkRoomMember(
            userId: '@bob:example.org',
            displayName: 'Bob Builder',
            powerLevel: 0,
          ),
        ],
        inviteMember: (_, _) async {},
      );

      final members = await port.searchMembers(
        roomId: '!room:example.org',
        query: 'builder',
      );
      final powers = await port.powerLevels('!room:example.org');

      expect(members, hasLength(1));
      expect(members.single.userId, '@bob:example.org');
      expect(members.single.membership, RoomMembership.joined);
      expect(powers.powerLevelFor('@alice:example.org'), 100);
      expect(powers.powerLevelFor('@unknown:example.org'), 0);
    },
  );

  test(
    'Matrix member adapter exposes only production-backed invite mutation',
    () async {
      final invites = <(String, String)>[];
      final port = MatrixRoomMemberManagementPort(
        loadMembers: (_) async => const <MatrixSdkRoomMember>[],
        inviteMember: (roomId, userId) async => invites.add((roomId, userId)),
      );

      final inviteAuthorization = await port.authorize(
        roomId: '!room:example.org',
        actorUserId: '@alice:example.org',
        action: RoomMemberAction.invite,
        targetUserId: '@bob:example.org',
      );
      final kickAuthorization = await port.authorize(
        roomId: '!room:example.org',
        actorUserId: '@alice:example.org',
        action: RoomMemberAction.kick,
        targetUserId: '@bob:example.org',
      );

      expect(inviteAuthorization.allowed, isTrue);
      expect(kickAuthorization.allowed, isFalse);

      await port.invite(
        roomId: '!room:example.org',
        userId: '@bob:example.org',
      );
      expect(invites, <(String, String)>[
        ('!room:example.org', '@bob:example.org'),
      ]);
    },
  );
}
