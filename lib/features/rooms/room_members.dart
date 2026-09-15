import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

enum RoomMembership { joined, invited, knocked, left, banned }

enum RoomMemberRole {
  administrator(100, 'Administrator'),
  moderator(50, 'Moderator'),
  member(0, 'Member');

  const RoomMemberRole(this.powerLevel, this.label);

  final int powerLevel;
  final String label;

  static RoomMemberRole fromPowerLevel(int powerLevel) {
    if (powerLevel >= administrator.powerLevel) return administrator;
    if (powerLevel >= moderator.powerLevel) return moderator;
    return member;
  }
}

@immutable
class RoomMember {
  const RoomMember({
    required this.userId,
    required this.displayName,
    required this.membership,
    required this.powerLevel,
  });

  final String userId;
  final String displayName;
  final RoomMembership membership;
  final int powerLevel;

  RoomMemberRole get role => RoomMemberRole.fromPowerLevel(powerLevel);

  RoomMember copyWith({
    String? displayName,
    RoomMembership? membership,
    int? powerLevel,
  }) {
    return RoomMember(
      userId: userId,
      displayName: displayName ?? this.displayName,
      membership: membership ?? this.membership,
      powerLevel: powerLevel ?? this.powerLevel,
    );
  }
}

@immutable
class MatrixPowerLevels {
  const MatrixPowerLevels({
    this.users = const <String, int>{},
    this.usersDefault = 0,
    this.invite = 0,
    this.kick = 50,
    this.ban = 50,
    this.stateDefault = 50,
    this.events = const <String, int>{},
  });

  final Map<String, int> users;
  final int usersDefault;
  final int invite;
  final int kick;
  final int ban;
  final int stateDefault;
  final Map<String, int> events;

  int powerLevelFor(String userId) => users[userId] ?? usersDefault;

  int requiredForStateEvent(String eventType) =>
      events[eventType] ?? stateDefault;
}

@immutable
class RoomModerationPermissions {
  const RoomModerationPermissions(this.powerLevels);

  final MatrixPowerLevels powerLevels;

  bool canChangeRole({
    required RoomMember actor,
    required RoomMember target,
    required RoomMemberRole role,
  }) {
    if (!_canTarget(actor, target) ||
        target.membership != RoomMembership.joined) {
      return false;
    }
    final actorLevel = powerLevels.powerLevelFor(actor.userId);
    final targetLevel = powerLevels.powerLevelFor(target.userId);
    final required = powerLevels.requiredForStateEvent('m.room.power_levels');
    return actorLevel >= required &&
        actorLevel > targetLevel &&
        actorLevel > role.powerLevel;
  }

  bool canKick({required RoomMember actor, required RoomMember target}) {
    if (!_canTarget(actor, target) ||
        target.membership != RoomMembership.joined) {
      return false;
    }
    final actorLevel = powerLevels.powerLevelFor(actor.userId);
    final targetLevel = powerLevels.powerLevelFor(target.userId);
    return actorLevel >= powerLevels.kick && actorLevel > targetLevel;
  }

  bool canBan({required RoomMember actor, required RoomMember target}) {
    if (!_canTarget(actor, target) ||
        target.membership == RoomMembership.banned) {
      return false;
    }
    final actorLevel = powerLevels.powerLevelFor(actor.userId);
    final targetLevel = powerLevels.powerLevelFor(target.userId);
    return actorLevel >= powerLevels.ban && actorLevel > targetLevel;
  }

  bool canUnban({required RoomMember actor, required RoomMember target}) {
    if (!_canTarget(actor, target) ||
        target.membership != RoomMembership.banned) {
      return false;
    }
    final actorLevel = powerLevels.powerLevelFor(actor.userId);
    final targetLevel = powerLevels.powerLevelFor(target.userId);
    return actorLevel >= powerLevels.kick &&
        actorLevel >= powerLevels.ban &&
        actorLevel > targetLevel;
  }

  bool _canTarget(RoomMember actor, RoomMember target) {
    return actor.membership == RoomMembership.joined &&
        actor.userId != target.userId;
  }
}

abstract interface class RoomModerationGateway {
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  });

  Future<void> kick({required String roomId, required String userId});

  Future<void> ban({required String roomId, required String userId});

  Future<void> unban({required String roomId, required String userId});
}

class InMemoryRoomModerationGateway implements RoomModerationGateway {
  @override
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {}

  @override
  Future<void> kick({required String roomId, required String userId}) async {}

  @override
  Future<void> ban({required String roomId, required String userId}) async {}

  @override
  Future<void> unban({required String roomId, required String userId}) async {}
}

class RoomMembersStore {
  RoomMembersStore({
    required this.roomId,
    required this.currentUserId,
    required List<RoomMember> members,
    required MatrixPowerLevels powerLevels,
    RoomModerationGateway? moderationGateway,
  }) : moderationGateway = moderationGateway ?? InMemoryRoomModerationGateway(),
       members = signal<List<RoomMember>>(
         List<RoomMember>.unmodifiable(members),
       ),
       powerLevels = signal<MatrixPowerLevels>(powerLevels);

  final String roomId;
  final String currentUserId;
  final RoomModerationGateway moderationGateway;
  final Signal<List<RoomMember>> members;
  final Signal<MatrixPowerLevels> powerLevels;
  final Signal<String> query = signal<String>('');

  RoomMember get currentUser => member(currentUserId);

  RoomMember member(String userId) =>
      members.value.firstWhere((member) => member.userId == userId);

  List<RoomMember> get visibleMembers {
    final normalized = query.value.trim().toLowerCase();
    final joined = members.value
        .where((member) => member.membership == RoomMembership.joined)
        .where((member) {
          if (normalized.isEmpty) return true;
          return member.displayName.toLowerCase().contains(normalized) ||
              member.userId.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
    joined.sort((left, right) {
      final byPower = right.powerLevel.compareTo(left.powerLevel);
      if (byPower != 0) return byPower;
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    });
    return joined;
  }

  RoomModerationPermissions get permissions =>
      RoomModerationPermissions(powerLevels.value);

  Future<bool> setRole(String userId, RoomMemberRole role) async {
    final target = member(userId);
    if (!permissions.canChangeRole(
      actor: currentUser,
      target: target,
      role: role,
    )) {
      return false;
    }
    try {
      await moderationGateway.setPowerLevel(
        roomId: roomId,
        userId: userId,
        powerLevel: role.powerLevel,
      );
    } on Exception {
      return false;
    }
    _replaceMember(target.copyWith(powerLevel: role.powerLevel));
    final nextUsers = Map<String, int>.of(powerLevels.value.users)
      ..[userId] = role.powerLevel;
    powerLevels.value = MatrixPowerLevels(
      users: Map<String, int>.unmodifiable(nextUsers),
      usersDefault: powerLevels.value.usersDefault,
      invite: powerLevels.value.invite,
      kick: powerLevels.value.kick,
      ban: powerLevels.value.ban,
      stateDefault: powerLevels.value.stateDefault,
      events: powerLevels.value.events,
    );
    return true;
  }

  Future<bool> kick(String userId) async {
    final target = member(userId);
    if (!permissions.canKick(actor: currentUser, target: target)) return false;
    try {
      await moderationGateway.kick(roomId: roomId, userId: userId);
    } on Exception {
      return false;
    }
    _replaceMember(target.copyWith(membership: RoomMembership.left));
    return true;
  }

  Future<bool> ban(String userId) async {
    final target = member(userId);
    if (!permissions.canBan(actor: currentUser, target: target)) return false;
    try {
      await moderationGateway.ban(roomId: roomId, userId: userId);
    } on Exception {
      return false;
    }
    _replaceMember(target.copyWith(membership: RoomMembership.banned));
    return true;
  }

  Future<bool> unban(String userId) async {
    final target = member(userId);
    if (!permissions.canUnban(actor: currentUser, target: target)) return false;
    try {
      await moderationGateway.unban(roomId: roomId, userId: userId);
    } on Exception {
      return false;
    }
    _replaceMember(target.copyWith(membership: RoomMembership.left));
    return true;
  }

  void _replaceMember(RoomMember updated) {
    members.value = List<RoomMember>.unmodifiable(<RoomMember>[
      for (final member in members.value)
        if (member.userId == updated.userId) updated else member,
    ]);
  }

  void dispose() {
    members.dispose();
    powerLevels.dispose();
    query.dispose();
  }
}

abstract final class RoomMembersFixture {
  static const String currentUserId = '@you:example.org';

  static RoomMembersStore forRoom(String roomId) {
    const members = <RoomMember>[
      RoomMember(
        userId: currentUserId,
        displayName: 'You',
        membership: RoomMembership.joined,
        powerLevel: 100,
      ),
      RoomMember(
        userId: '@alice:example.org',
        displayName: 'Alice',
        membership: RoomMembership.joined,
        powerLevel: 50,
      ),
      RoomMember(
        userId: '@bob:example.org',
        displayName: 'Bob',
        membership: RoomMembership.joined,
        powerLevel: 0,
      ),
      RoomMember(
        userId: '@charlie:example.org',
        displayName: 'Charlie',
        membership: RoomMembership.joined,
        powerLevel: 0,
      ),
      RoomMember(
        userId: '@dana:example.org',
        displayName: 'Dana',
        membership: RoomMembership.joined,
        powerLevel: 0,
      ),
    ];
    const levels = MatrixPowerLevels(
      users: <String, int>{currentUserId: 100, '@alice:example.org': 50},
      events: <String, int>{'m.room.power_levels': 50},
    );
    return RoomMembersStore(
      roomId: roomId,
      currentUserId: currentUserId,
      members: members,
      powerLevels: levels,
    );
  }
}
