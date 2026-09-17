import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

typedef MatrixRoomMembersLookup = Future<List<MatrixSdkRoomMember>> Function(
  String roomId,
);
typedef MatrixRoomMemberInvite = Future<void> Function(
  String roomId,
  String userId,
);
typedef MatrixRoomMemberAuthorization = Future<bool> Function(
  String roomId,
  String actorUserId,
  String targetUserId,
  MatrixSdkRoomMemberAction action,
  int? requestedPowerLevel,
);
typedef MatrixRoomMemberPowerLevelMutation = Future<void> Function(
  String roomId,
  String userId,
  int powerLevel,
);
typedef MatrixRoomMemberMutation = Future<void> Function(
  String roomId,
  String userId,
);
typedef MatrixRoomMemberBan = Future<void> Function(
  String roomId,
  String userId,
  String? reason,
);

final class MatrixRoomMemberManagementPort
    implements
        RoomMemberDirectoryPort,
        RoomMemberAuthorizationPort,
        RoomMemberMutationPort {
  const MatrixRoomMemberManagementPort({
    required this._loadMembers,
    required this._inviteMember,
    required this._authorizeMember,
    required this._setPowerLevel,
    required this._kickMember,
    required this._banMember,
    required this._unbanMember,
  });

  final MatrixRoomMembersLookup _loadMembers;
  final MatrixRoomMemberInvite _inviteMember;
  final MatrixRoomMemberAuthorization _authorizeMember;
  final MatrixRoomMemberPowerLevelMutation _setPowerLevel;
  final MatrixRoomMemberMutation _kickMember;
  final MatrixRoomMemberBan _banMember;
  final MatrixRoomMemberMutation _unbanMember;

  @override
  Future<List<RoomMember>> searchMembers({
    required String roomId,
    required String query,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final members = await _loadMembers(roomId);
    return List<RoomMember>.unmodifiable(
      members
          .where((member) {
            if (normalizedQuery.isEmpty) return true;
            return member.userId.toLowerCase().contains(normalizedQuery) ||
                member.displayName.toLowerCase().contains(normalizedQuery);
          })
          .map(
            (member) => RoomMember(
              userId: member.userId,
              displayName: member.displayName,
              membership: RoomMembership.joined,
              powerLevel: member.powerLevel,
            ),
          ),
    );
  }

  @override
  Future<RoomPowerLevelSummary> powerLevels(String roomId) async {
    final members = await _loadMembers(roomId);
    return RoomPowerLevelSummary(
      members: <String, int>{
        for (final member in members) member.userId: member.powerLevel,
      },
      defaultUserPowerLevel: 0,
    );
  }

  @override
  Future<RoomMemberActionAuthorization> authorize({
    required String roomId,
    required String actorUserId,
    required RoomMemberAction action,
    String? targetUserId,
    int? requestedPowerLevel,
  }) async {
    final target = targetUserId?.trim();
    if (target == null || target.isEmpty) {
      return const RoomMemberActionAuthorization.denied(
        'This room action needs a target member.',
      );
    }
    final sdkAction = switch (action) {
      RoomMemberAction.invite => MatrixSdkRoomMemberAction.invite,
      RoomMemberAction.changePowerLevel =>
        MatrixSdkRoomMemberAction.changePowerLevel,
      RoomMemberAction.kick => MatrixSdkRoomMemberAction.kick,
      RoomMemberAction.ban => MatrixSdkRoomMemberAction.ban,
      RoomMemberAction.unban => MatrixSdkRoomMemberAction.unban,
    };
    final allowed = await _authorizeMember(
      roomId,
      actorUserId,
      target,
      sdkAction,
      requestedPowerLevel,
    );
    return allowed
        ? const RoomMemberActionAuthorization.allowed()
        : const RoomMemberActionAuthorization.denied(
            'You do not have permission for this room action.',
          );
  }

  @override
  Future<void> invite({required String roomId, required String userId}) =>
      _inviteMember(roomId, userId);

  @override
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) => _setPowerLevel(roomId, userId, powerLevel);

  @override
  Future<void> kick({required String roomId, required String userId}) =>
      _kickMember(roomId, userId);

  @override
  Future<void> ban({
    required String roomId,
    required String userId,
    String? reason,
  }) => _banMember(roomId, userId, reason);

  @override
  Future<void> unban({required String roomId, required String userId}) =>
      _unbanMember(roomId, userId);

  @override
  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) => _unsupported();

  @override
  Future<void> reportRoom({required String roomId, String? reason}) =>
      _unsupported();

  @override
  Future<void> leave({required String roomId}) => _unsupported();

  @override
  Future<void> forget({required String roomId}) => _unsupported();

  Future<void> _unsupported() => Future<void>.error(
    UnsupportedError(
      'Room member mutation is not available through this port.',
    ),
  );
}
