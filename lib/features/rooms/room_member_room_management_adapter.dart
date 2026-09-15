import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart';

final class LifecycleAwareRoomMemberMutationPort
    implements RoomMemberMutationPort {
  const LifecycleAwareRoomMemberMutationPort({
    required this.memberMutations,
    required this.roomManagement,
  });

  final RoomMemberMutationPort memberMutations;
  final RoomManagementCoordinator roomManagement;

  @override
  Future<void> leave({required String roomId}) =>
      roomManagement.leaveRoom(roomId);

  @override
  Future<void> forget({required String roomId}) =>
      roomManagement.forgetRoom(roomId);

  @override
  Future<void> invite({required String roomId, required String userId}) =>
      memberMutations.invite(roomId: roomId, userId: userId);

  @override
  Future<void> setPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) => memberMutations.setPowerLevel(
    roomId: roomId,
    userId: userId,
    powerLevel: powerLevel,
  );

  @override
  Future<void> kick({required String roomId, required String userId}) =>
      memberMutations.kick(roomId: roomId, userId: userId);

  @override
  Future<void> ban({
    required String roomId,
    required String userId,
    String? reason,
  }) => memberMutations.ban(roomId: roomId, userId: userId, reason: reason);

  @override
  Future<void> unban({required String roomId, required String userId}) =>
      memberMutations.unban(roomId: roomId, userId: userId);

  @override
  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) =>
      roomManagement.reportUser(roomId: roomId, userId: userId, reason: reason);

  @override
  Future<void> reportRoom({required String roomId, String? reason}) =>
      roomManagement.reportRoom(roomId: roomId, reason: reason);
}
