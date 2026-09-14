import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/room_members.dart';

void main() {
  group('Matrix power-level semantics', () {
    test('uses Matrix defaults for membership moderation', () {
      const levels = MatrixPowerLevels();

      expect(levels.usersDefault, 0);
      expect(levels.invite, 0);
      expect(levels.kick, 50);
      expect(levels.ban, 50);
      expect(levels.stateDefault, 50);
      expect(levels.powerLevelFor('@nobody:example.org'), 0);
      expect(levels.requiredForStateEvent('m.room.name'), 50);
    });

    test('explicit power-level event requirement overrides state default', () {
      const levels = MatrixPowerLevels(
        stateDefault: 70,
        events: <String, int>{'m.room.power_levels': 90},
      );

      expect(levels.requiredForStateEvent('m.room.power_levels'), 90);
      expect(levels.requiredForStateEvent('m.room.topic'), 70);
    });
  });

  group('Room member list and moderation', () {
    late RoomMembersStore store;

    setUp(() {
      store = RoomMembersFixture.forRoom('kite');
    });

    tearDown(() {
      store.dispose();
    });

    test('searches display names and Matrix user IDs deterministically', () {
      expect(store.visibleMembers.map((member) => member.displayName), <String>[
        'You',
        'Alice',
        'Bob',
        'Charlie',
        'Dana',
      ]);

      store.query.value = 'ali';
      expect(store.visibleMembers.single.userId, '@alice:example.org');

      store.query.value = '@BOB:';
      expect(store.visibleMembers.single.displayName, 'Bob');

      store.query.value = 'missing';
      expect(store.visibleMembers, isEmpty);
    });

    test('maps power levels to user-facing room roles', () {
      expect(
        store.member(RoomMembersFixture.currentUserId).role,
        RoomMemberRole.administrator,
      );
      expect(store.member('@alice:example.org').role, RoomMemberRole.moderator);
      expect(store.member('@bob:example.org').role, RoomMemberRole.member);
    });

    test('administrator can promote and demote lower-power members', () async {
      expect(
        await store.setRole('@bob:example.org', RoomMemberRole.moderator),
        isTrue,
      );
      expect(store.member('@bob:example.org').powerLevel, 50);
      expect(store.powerLevels.value.powerLevelFor('@bob:example.org'), 50);

      expect(
        await store.setRole('@bob:example.org', RoomMemberRole.member),
        isTrue,
      );
      expect(store.member('@bob:example.org').powerLevel, 0);
    });

    test('cannot assign a power level equal to the actor', () async {
      expect(
        await store.setRole('@alice:example.org', RoomMemberRole.administrator),
        isFalse,
      );
      expect(store.member('@alice:example.org').powerLevel, 50);
    });

    test('equal-power users cannot moderate each other', () {
      final equalPowerMembers = <RoomMember>[
        for (final member in store.members.value)
          if (member.userId == '@alice:example.org')
            member.copyWith(powerLevel: 100)
          else
            member,
      ];
      const equalPowerLevels = MatrixPowerLevels(
        users: <String, int>{
          RoomMembersFixture.currentUserId: 100,
          '@alice:example.org': 100,
        },
        events: <String, int>{'m.room.power_levels': 50},
      );
      final equalPowerStore = RoomMembersStore(
        roomId: 'kite',
        currentUserId: RoomMembersFixture.currentUserId,
        members: equalPowerMembers,
        powerLevels: equalPowerLevels,
      );
      addTearDown(equalPowerStore.dispose);
      final alice = equalPowerStore.member('@alice:example.org');
      final you = equalPowerStore.currentUser;

      expect(
        equalPowerStore.permissions.canKick(actor: you, target: alice),
        isFalse,
      );
      expect(
        equalPowerStore.permissions.canChangeRole(
          actor: you,
          target: alice,
          role: RoomMemberRole.member,
        ),
        isFalse,
      );
    });

    test('kick requires threshold and strictly greater target power', () async {
      expect(await store.kick('@bob:example.org'), isTrue);
      expect(store.member('@bob:example.org').membership, RoomMembership.left);
      expect(
        store.visibleMembers.any(
          (member) => member.userId == '@bob:example.org',
        ),
        isFalse,
      );

      expect(await store.kick('@alice:example.org'), isTrue);
      expect(
        store.member('@alice:example.org').membership,
        RoomMembership.left,
      );
      expect(await store.kick(RoomMembersFixture.currentUserId), isFalse);
    });

    test('ban and unban follow Matrix membership thresholds', () async {
      expect(await store.ban('@bob:example.org'), isTrue);
      expect(
        store.member('@bob:example.org').membership,
        RoomMembership.banned,
      );
      expect(await store.ban('@bob:example.org'), isFalse);

      expect(await store.unban('@bob:example.org'), isTrue);
      expect(store.member('@bob:example.org').membership, RoomMembership.left);
      expect(await store.unban('@bob:example.org'), isFalse);
    });

    test('moderator cannot kick a peer or promote to own power', () async {
      final moderatorStore = RoomMembersStore(
        roomId: 'kite',
        currentUserId: '@alice:example.org',
        members: store.members.value,
        powerLevels: store.powerLevels.value,
      );
      addTearDown(moderatorStore.dispose);

      expect(await moderatorStore.kick('@bob:example.org'), isTrue);
      expect(
        await moderatorStore.setRole(
          '@charlie:example.org',
          RoomMemberRole.administrator,
        ),
        isFalse,
      );
      expect(
        await moderatorStore.setRole(
          '@charlie:example.org',
          RoomMemberRole.moderator,
        ),
        isFalse,
      );
    });
    test('gateway failure never mutates local moderation state', () async {
      final gateway = _FailingModerationGateway();
      final failingStore = RoomMembersStore(
        roomId: 'kite',
        currentUserId: RoomMembersFixture.currentUserId,
        members: store.members.value,
        powerLevels: store.powerLevels.value,
        moderationGateway: gateway,
      );
      addTearDown(failingStore.dispose);

      expect(
        await failingStore.setRole(
          '@bob:example.org',
          RoomMemberRole.moderator,
        ),
        isFalse,
      );
      expect(failingStore.member('@bob:example.org').powerLevel, 0);
      expect(await failingStore.kick('@bob:example.org'), isFalse);
      expect(
        failingStore.member('@bob:example.org').membership,
        RoomMembership.joined,
      );
    });
  });
}

class _FailingModerationGateway implements RoomModerationGateway {
  Never _fail() => throw Exception('deterministic moderation failure');

  @override
  Future<void> ban({required String roomId, required String userId}) async {
    _fail();
  }

  @override
  Future<void> kick({required String roomId, required String userId}) async {
    _fail();
  }

  @override
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {
    _fail();
  }

  @override
  Future<void> unban({required String roomId, required String userId}) async {
    _fail();
  }
}
