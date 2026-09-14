import 'package:kite/features/rooms/room_member_management.dart';

final class RoomMemberAuthorizationRequest {
  const RoomMemberAuthorizationRequest({
    required this.roomId,
    required this.actorUserId,
    required this.action,
    required this.targetUserId,
    required this.requestedPowerLevel,
  });

  final String roomId;
  final String actorUserId;
  final RoomMemberAction action;
  final String? targetUserId;
  final int? requestedPowerLevel;
}

final class FakeRoomMemberDirectoryPort implements RoomMemberDirectoryPort {
  FakeRoomMemberDirectoryPort({
    Iterable<RoomMember> members = const <RoomMember>[],
    RoomPowerLevelSummary? powerLevels,
  }) : _members = List<RoomMember>.of(members),
       _powerLevels =
           powerLevels ??
           RoomPowerLevelSummary(
             members: const <String, int>{},
             defaultUserPowerLevel: 0,
           );

  final List<RoomMember> _members;
  final RoomPowerLevelSummary _powerLevels;
  final List<String> queries = <String>[];

  @override
  Future<RoomPowerLevelSummary> powerLevels(String roomId) async =>
      _powerLevels;

  @override
  Future<List<RoomMember>> searchMembers({
    required String roomId,
    required String query,
  }) async {
    queries.add(query);
    final normalized = query.toLowerCase();
    if (normalized.isEmpty) return List<RoomMember>.of(_members);
    return _members
        .where(
          (member) =>
              member.userId.toLowerCase().contains(normalized) ||
              member.displayName.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }
}

final class FakeRoomMemberAuthorizationPort
    implements RoomMemberAuthorizationPort {
  factory FakeRoomMemberAuthorizationPort({
    RoomMemberActionAuthorization fallback =
        const RoomMemberActionAuthorization.allowed(),
  }) => FakeRoomMemberAuthorizationPort._(fallback);

  FakeRoomMemberAuthorizationPort._(this._fallback);

  final RoomMemberActionAuthorization _fallback;
  final Map<RoomMemberAction, RoomMemberActionAuthorization> decisions =
      <RoomMemberAction, RoomMemberActionAuthorization>{};
  final List<RoomMemberAuthorizationRequest> requests =
      <RoomMemberAuthorizationRequest>[];

  @override
  Future<RoomMemberActionAuthorization> authorize({
    required String roomId,
    required String actorUserId,
    required RoomMemberAction action,
    String? targetUserId,
    int? requestedPowerLevel,
  }) async {
    requests.add(
      RoomMemberAuthorizationRequest(
        roomId: roomId,
        actorUserId: actorUserId,
        action: action,
        targetUserId: targetUserId,
        requestedPowerLevel: requestedPowerLevel,
      ),
    );
    return decisions[action] ?? _fallback;
  }
}

final class FakeRoomMemberMutationPort implements RoomMemberMutationPort {
  final List<({String roomId, String userId})> invitations =
      <({String roomId, String userId})>[];
  final List<({String roomId, String userId, int powerLevel})>
  powerLevelChanges = <({String roomId, String userId, int powerLevel})>[];
  final List<({String roomId, String userId})> kicks =
      <({String roomId, String userId})>[];

  @override
  Future<void> invite({required String roomId, required String userId}) async {
    invitations.add((roomId: roomId, userId: userId));
  }

  @override
  Future<void> kick({required String roomId, required String userId}) async {
    kicks.add((roomId: roomId, userId: userId));
  }

  @override
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {
    powerLevelChanges.add((
      roomId: roomId,
      userId: userId,
      powerLevel: powerLevel,
    ));
  }
}
