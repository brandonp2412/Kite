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
        authorizeMember: (_, _, _, _, _) async => true,
        setPowerLevel: (_, _, _) async {},
        kickMember: (_, _) async {},
        banMember: (_, _, _) async {},
        unbanMember: (_, _) async {},
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

  test('Matrix member adapter routes SDK-authorised moderation', () async {
    final authorizations =
        <(String, String, String, MatrixSdkRoomMemberAction, int?)>[];
    final invites = <(String, String)>[];
    final powerChanges = <(String, String, int)>[];
    final kicks = <(String, String)>[];
    final bans = <(String, String, String?)>[];
    final unbans = <(String, String)>[];
    final port = MatrixRoomMemberManagementPort(
      loadMembers: (_) async => const <MatrixSdkRoomMember>[],
      inviteMember: (roomId, userId) async => invites.add((roomId, userId)),
      authorizeMember:
          (
            roomId,
            actorUserId,
            targetUserId,
            action,
            requestedPowerLevel,
          ) async {
            authorizations.add((
              roomId,
              actorUserId,
              targetUserId,
              action,
              requestedPowerLevel,
            ));
            return action != MatrixSdkRoomMemberAction.ban;
          },
      setPowerLevel: (roomId, userId, powerLevel) async =>
          powerChanges.add((roomId, userId, powerLevel)),
      kickMember: (roomId, userId) async => kicks.add((roomId, userId)),
      banMember: (roomId, userId, reason) async =>
          bans.add((roomId, userId, reason)),
      unbanMember: (roomId, userId) async => unbans.add((roomId, userId)),
    );

    final inviteAuthorization = await port.authorize(
      roomId: '!room:example.org',
      actorUserId: '@alice:example.org',
      action: RoomMemberAction.invite,
      targetUserId: '@bob:example.org',
    );
    final roleAuthorization = await port.authorize(
      roomId: '!room:example.org',
      actorUserId: '@alice:example.org',
      action: RoomMemberAction.changePowerLevel,
      targetUserId: '@bob:example.org',
      requestedPowerLevel: 50,
    );
    final banAuthorization = await port.authorize(
      roomId: '!room:example.org',
      actorUserId: '@alice:example.org',
      action: RoomMemberAction.ban,
      targetUserId: '@bob:example.org',
    );

    expect(inviteAuthorization.allowed, isTrue);
    expect(roleAuthorization.allowed, isTrue);
    expect(banAuthorization.allowed, isFalse);
    expect(
      authorizations,
      <(String, String, String, MatrixSdkRoomMemberAction, int?)>[
        (
          '!room:example.org',
          '@alice:example.org',
          '@bob:example.org',
          MatrixSdkRoomMemberAction.invite,
          null,
        ),
        (
          '!room:example.org',
          '@alice:example.org',
          '@bob:example.org',
          MatrixSdkRoomMemberAction.changePowerLevel,
          50,
        ),
        (
          '!room:example.org',
          '@alice:example.org',
          '@bob:example.org',
          MatrixSdkRoomMemberAction.ban,
          null,
        ),
      ],
    );

    await port.invite(roomId: '!room:example.org', userId: '@bob:example.org');
    await port.setPowerLevel(
      roomId: '!room:example.org',
      userId: '@bob:example.org',
      powerLevel: 50,
    );
    await port.kick(roomId: '!room:example.org', userId: '@bob:example.org');
    await port.ban(
      roomId: '!room:example.org',
      userId: '@bob:example.org',
      reason: 'spam',
    );
    await port.unban(roomId: '!room:example.org', userId: '@bob:example.org');

    expect(invites, <(String, String)>[
      ('!room:example.org', '@bob:example.org'),
    ]);
    expect(powerChanges, <(String, String, int)>[
      ('!room:example.org', '@bob:example.org', 50),
    ]);
    expect(kicks, <(String, String)>[
      ('!room:example.org', '@bob:example.org'),
    ]);
    expect(bans, <(String, String, String?)>[
      ('!room:example.org', '@bob:example.org', 'spam'),
    ]);
    expect(unbans, <(String, String)>[
      ('!room:example.org', '@bob:example.org'),
    ]);
  });
}
