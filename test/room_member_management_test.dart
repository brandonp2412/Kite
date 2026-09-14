import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

void main() {
  const roomId = '!room:example.org';
  const actorUserId = '@moderator:example.org';

  RoomMemberManagementCoordinator coordinator({
    FakeRoomMemberDirectoryPort? directory,
    FakeRoomMemberAuthorizationPort? authorization,
    FakeRoomMemberMutationPort? mutations,
  }) {
    return RoomMemberManagementCoordinator(
      actorUserId: actorUserId,
      directory: directory ?? FakeRoomMemberDirectoryPort(),
      authorization: authorization ?? FakeRoomMemberAuthorizationPort(),
      mutations: mutations ?? FakeRoomMemberMutationPort(),
    );
  }

  group('member discovery', () {
    test('search trims the query and returns an immutable result', () async {
      final directory = FakeRoomMemberDirectoryPort(
        members: const <RoomMember>[
          RoomMember(
            userId: '@alice:example.org',
            displayName: 'Alice',
            membership: RoomMembership.joined,
            powerLevel: 0,
          ),
          RoomMember(
            userId: '@bob:example.org',
            displayName: 'Bob',
            membership: RoomMembership.joined,
            powerLevel: 50,
          ),
        ],
      );
      final subject = coordinator(directory: directory);

      final result = await subject.searchMembers(
        roomId: roomId,
        query: '  ALI  ',
      );

      expect(directory.queries, <String>['ALI']);
      expect(result.map((member) => member.userId), <String>[
        '@alice:example.org',
      ]);
      expect(
        () => result.add(
          const RoomMember(
            userId: '@mallory:example.org',
            displayName: 'Mallory',
            membership: RoomMembership.joined,
            powerLevel: 0,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('power-level summary preserves SDK supplied room values', () async {
      final levels = RoomPowerLevelSummary(
        members: const <String, int>{
          actorUserId: 50,
          '@owner:example.org': 100,
        },
        defaultUserPowerLevel: 0,
      );
      final subject = coordinator(
        directory: FakeRoomMemberDirectoryPort(powerLevels: levels),
      );

      final result = await subject.powerLevels(roomId);

      expect(result.powerLevelFor(actorUserId), 50);
      expect(result.powerLevelFor('@owner:example.org'), 100);
      expect(result.powerLevelFor('@member:example.org'), 0);
    });
  });

  group('member mutations', () {
    test('invite checks SDK authorization before mutation', () async {
      final authorization = FakeRoomMemberAuthorizationPort();
      final mutations = FakeRoomMemberMutationPort();
      final subject = coordinator(
        authorization: authorization,
        mutations: mutations,
      );

      await subject.invite(roomId: roomId, userId: '@invitee:example.org');

      expect(authorization.requests, hasLength(1));
      final request = authorization.requests.single;
      expect(request.roomId, roomId);
      expect(request.actorUserId, actorUserId);
      expect(request.action, RoomMemberAction.invite);
      expect(request.targetUserId, '@invitee:example.org');
      expect(mutations.invitations, <({String roomId, String userId})>[
        (roomId: roomId, userId: '@invitee:example.org'),
      ]);
    });

    test('denied invite never reaches the mutation port', () async {
      final authorization = FakeRoomMemberAuthorizationPort();
      authorization.decisions[RoomMemberAction.invite] =
          const RoomMemberActionAuthorization.denied('Invite not permitted.');
      final mutations = FakeRoomMemberMutationPort();
      final subject = coordinator(
        authorization: authorization,
        mutations: mutations,
      );

      expect(
        () => subject.invite(roomId: roomId, userId: '@invitee:example.org'),
        throwsA(
          isA<RoomMemberActionDenied>()
              .having(
                (error) => error.action,
                'action',
                RoomMemberAction.invite,
              )
              .having(
                (error) => error.reason,
                'reason',
                'Invite not permitted.',
              ),
        ),
      );
      expect(mutations.invitations, isEmpty);
    });

    test(
      'power-level change delegates exact target level to SDK guard',
      () async {
        final authorization = FakeRoomMemberAuthorizationPort();
        final mutations = FakeRoomMemberMutationPort();
        final subject = coordinator(
          authorization: authorization,
          mutations: mutations,
        );

        await subject.setPowerLevel(
          roomId: roomId,
          userId: '@member:example.org',
          powerLevel: 50,
        );

        final request = authorization.requests.single;
        expect(request.action, RoomMemberAction.changePowerLevel);
        expect(request.targetUserId, '@member:example.org');
        expect(request.requestedPowerLevel, 50);
        expect(
          mutations.powerLevelChanges,
          <({String roomId, String userId, int powerLevel})>[
            (roomId: roomId, userId: '@member:example.org', powerLevel: 50),
          ],
        );
      },
    );

    test('denied promotion or demotion never changes power levels', () async {
      final authorization = FakeRoomMemberAuthorizationPort();
      authorization.decisions[RoomMemberAction.changePowerLevel] =
          const RoomMemberActionAuthorization.denied(
            'Power level change not permitted.',
          );
      final mutations = FakeRoomMemberMutationPort();
      final subject = coordinator(
        authorization: authorization,
        mutations: mutations,
      );

      expect(
        () => subject.setPowerLevel(
          roomId: roomId,
          userId: '@member:example.org',
          powerLevel: 100,
        ),
        throwsA(isA<RoomMemberActionDenied>()),
      );
      expect(mutations.powerLevelChanges, isEmpty);
    });

    test('kick checks SDK authorization before mutation', () async {
      final authorization = FakeRoomMemberAuthorizationPort();
      final mutations = FakeRoomMemberMutationPort();
      final subject = coordinator(
        authorization: authorization,
        mutations: mutations,
      );

      await subject.kick(roomId: roomId, userId: '@member:example.org');

      final request = authorization.requests.single;
      expect(request.action, RoomMemberAction.kick);
      expect(request.targetUserId, '@member:example.org');
      expect(mutations.kicks, <({String roomId, String userId})>[
        (roomId: roomId, userId: '@member:example.org'),
      ]);
    });

    test('denied kick never reaches the mutation port', () async {
      final authorization = FakeRoomMemberAuthorizationPort();
      authorization.decisions[RoomMemberAction.kick] =
          const RoomMemberActionAuthorization.denied('Kick not permitted.');
      final mutations = FakeRoomMemberMutationPort();
      final subject = coordinator(
        authorization: authorization,
        mutations: mutations,
      );

      expect(
        () => subject.kick(roomId: roomId, userId: '@member:example.org'),
        throwsA(isA<RoomMemberActionDenied>()),
      );
      expect(mutations.kicks, isEmpty);
    });
  });
}
