import 'dart:collection';

enum RoomMembership { joined, invited, knocked, left, banned }

enum RoomMemberAction { invite, changePowerLevel, kick }

final class RoomMember {
  const RoomMember({
    required this.userId,
    required this.displayName,
    required this.membership,
    required this.powerLevel,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final RoomMembership membership;
  final int powerLevel;
  final Uri? avatarUrl;
}

final class RoomPowerLevelSummary {
  RoomPowerLevelSummary({
    required Map<String, int> members,
    required this.defaultUserPowerLevel,
  }) : members = UnmodifiableMapView<String, int>(Map<String, int>.of(members));

  final Map<String, int> members;
  final int defaultUserPowerLevel;

  int powerLevelFor(String userId) => members[userId] ?? defaultUserPowerLevel;
}

final class RoomMemberActionAuthorization {
  const RoomMemberActionAuthorization.allowed() : allowed = true, reason = null;

  const RoomMemberActionAuthorization.denied(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

final class RoomMemberActionDenied implements Exception {
  const RoomMemberActionDenied({required this.action, required this.reason});

  final RoomMemberAction action;
  final String reason;

  @override
  String toString() => 'RoomMemberActionDenied($action, $reason)';
}

abstract interface class RoomMemberDirectoryPort {
  Future<List<RoomMember>> searchMembers({
    required String roomId,
    required String query,
  });

  Future<RoomPowerLevelSummary> powerLevels(String roomId);
}

abstract interface class RoomMemberAuthorizationPort {
  Future<RoomMemberActionAuthorization> authorize({
    required String roomId,
    required String actorUserId,
    required RoomMemberAction action,
    String? targetUserId,
    int? requestedPowerLevel,
  });
}

abstract interface class RoomMemberMutationPort {
  Future<void> invite({required String roomId, required String userId});

  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  });

  Future<void> kick({required String roomId, required String userId});
}

final class RoomMemberManagementCoordinator {
  factory RoomMemberManagementCoordinator({
    required String actorUserId,
    required RoomMemberDirectoryPort directory,
    required RoomMemberAuthorizationPort authorization,
    required RoomMemberMutationPort mutations,
  }) => RoomMemberManagementCoordinator._(
    actorUserId,
    directory,
    authorization,
    mutations,
  );

  const RoomMemberManagementCoordinator._(
    this._actorUserId,
    this._directory,
    this._authorization,
    this._mutations,
  );

  final String _actorUserId;
  final RoomMemberDirectoryPort _directory;
  final RoomMemberAuthorizationPort _authorization;
  final RoomMemberMutationPort _mutations;

  Future<List<RoomMember>> searchMembers({
    required String roomId,
    String query = '',
  }) async {
    final members = await _directory.searchMembers(
      roomId: roomId,
      query: query.trim(),
    );
    return List<RoomMember>.unmodifiable(members);
  }

  Future<RoomPowerLevelSummary> powerLevels(String roomId) =>
      _directory.powerLevels(roomId);

  Future<void> invite({required String roomId, required String userId}) async {
    await _requireAuthorization(
      roomId: roomId,
      action: RoomMemberAction.invite,
      targetUserId: userId,
    );
    await _mutations.invite(roomId: roomId, userId: userId);
  }

  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {
    await _requireAuthorization(
      roomId: roomId,
      action: RoomMemberAction.changePowerLevel,
      targetUserId: userId,
      requestedPowerLevel: powerLevel,
    );
    await _mutations.setPowerLevel(
      roomId: roomId,
      userId: userId,
      powerLevel: powerLevel,
    );
  }

  Future<void> kick({required String roomId, required String userId}) async {
    await _requireAuthorization(
      roomId: roomId,
      action: RoomMemberAction.kick,
      targetUserId: userId,
    );
    await _mutations.kick(roomId: roomId, userId: userId);
  }

  Future<void> _requireAuthorization({
    required String roomId,
    required RoomMemberAction action,
    String? targetUserId,
    int? requestedPowerLevel,
  }) async {
    final authorization = await _authorization.authorize(
      roomId: roomId,
      actorUserId: _actorUserId,
      action: action,
      targetUserId: targetUserId,
      requestedPowerLevel: requestedPowerLevel,
    );
    if (authorization.allowed) return;

    throw RoomMemberActionDenied(
      action: action,
      reason: authorization.reason ?? 'Not authorised by the Matrix SDK.',
    );
  }
}
