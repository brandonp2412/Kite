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

    test('administrator can promote and demote lower-power members', () {
      expect(
        store.setRole('@bob:example.org', RoomMemberRole.moderator),
        isTrue,
      );
      expect(store.member('@bob:example.org').powerLevel, 50);
      expect(store.powerLevels.value.powerLevelFor('@bob:example.org'), 50);

      expect(store.setRole('@bob:example.org', RoomMemberRole.member), isTrue);
      expect(store.member('@bob:example.org').powerLevel, 0);
    });

    test('equal-power users cannot moderate each other', () {
      expect(
        store.setRole('@alice:example.org', RoomMemberRole.administrator),
        isTrue,
      );
      final alice = store.member('@alice:example.org');
      final you = store.currentUser;

      expect(alice.powerLevel, 100);
      expect(store.permissions.canKick(actor: you, target: alice), isFalse);
      expect(
        store.permissions.canChangeRole(
          actor: you,
          target: alice,
          role: RoomMemberRole.member,
        ),
        isFalse,
      );
    });

    test('kick requires threshold and strictly greater target power', () {
      expect(store.kick('@bob:example.org'), isTrue);
      expect(store.member('@bob:example.org').membership, RoomMembership.left);
      expect(
        store.visibleMembers.any(
          (member) => member.userId == '@bob:example.org',
        ),
        isFalse,
      );

      expect(store.kick('@alice:example.org'), isTrue);
      expect(
        store.member('@alice:example.org').membership,
        RoomMembership.left,
      );
      expect(store.kick(RoomMembersFixture.currentUserId), isFalse);
    });

    test('moderator cannot kick a peer or promote above own power', () {
      final moderatorStore = RoomMembersStore(
        currentUserId: '@alice:example.org',
        members: store.members.value,
        powerLevels: store.powerLevels.value,
      );
      addTearDown(moderatorStore.dispose);

      expect(moderatorStore.kick('@bob:example.org'), isTrue);
      expect(
        moderatorStore.setRole(
          '@charlie:example.org',
          RoomMemberRole.administrator,
        ),
        isFalse,
      );
      expect(
        moderatorStore.setRole(
          '@charlie:example.org',
          RoomMemberRole.moderator,
        ),
        isTrue,
      );
      expect(moderatorStore.kick('@charlie:example.org'), isFalse);
    });
  });
}
