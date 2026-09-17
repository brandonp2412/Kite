import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

typedef MatrixRoomCreate = Future<MatrixSdkCreatedRoom> Function(
  MatrixSdkRoomCreationRequest request,
);

final class MatrixRoomCreationManagementPort implements RoomManagementPort {
  const MatrixRoomCreationManagementPort(this._create);

  final MatrixRoomCreate _create;

  @override
  Future<KiteRoomCapabilities> capabilities() async => KiteRoomCapabilities(
    canCreatePublicRooms: true,
    supportedJoinRules: const <KiteRoomJoinRule>{
      KiteRoomJoinRule.invite,
      KiteRoomJoinRule.public,
    },
  );

  @override
  Future<KiteCreatedRoom> createRoom(KiteRoomCreationRequest request) async {
    final created = await _create(
      MatrixSdkRoomCreationRequest(
        kind: switch (request.kind) {
          KiteRoomCreationKind.directMessage =>
            MatrixSdkRoomCreationKind.directMessage,
          KiteRoomCreationKind.privateRoom =>
            MatrixSdkRoomCreationKind.privateRoom,
          KiteRoomCreationKind.publicRoom =>
            MatrixSdkRoomCreationKind.publicRoom,
        },
        name: request.name,
        topic: request.topic,
        invitees: request.invitees,
        joinRule: request.joinRule.name,
        encryptionEnabled: request.encryptionEnabled,
        historyVisibility: request.historyVisibility.name,
        canonicalAlias: request.canonicalAlias,
        parentSpaceId: request.parentSpaceId,
      ),
    );
    return KiteCreatedRoom(roomId: created.roomId, isDirect: created.isDirect);
  }

  @override
  Future<KiteRoomDetails> roomDetails(String roomId) => _unsupported();

  @override
  Future<void> setName({required String roomId, required String? name}) =>
      _unsupported();

  @override
  Future<void> setTopic({required String roomId, required String? topic}) =>
      _unsupported();

  @override
  Future<void> setAvatar({required String roomId, required Uri? avatarUrl}) =>
      _unsupported();

  @override
  Future<void> setCanonicalAlias({
    required String roomId,
    required String? canonicalAlias,
  }) => _unsupported();

  @override
  Future<void> setJoinRule({
    required String roomId,
    required KiteRoomJoinRule joinRule,
  }) => _unsupported();

  @override
  Future<void> enableEncryption(String roomId) => _unsupported();

  @override
  Future<void> setHistoryVisibility({
    required String roomId,
    required KiteRoomHistoryVisibility visibility,
  }) => _unsupported();

  @override
  Future<void> setNotificationMode({
    required String roomId,
    required KiteRoomNotificationMode mode,
  }) => _unsupported();

  @override
  Future<void> reportRoom({required String roomId, String? reason}) =>
      _unsupported();

  @override
  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) => _unsupported();

  @override
  Future<void> leaveRoom(String roomId) => _unsupported();

  @override
  Future<void> forgetRoom(String roomId) => _unsupported();

  Future<T> _unsupported<T>() => Future<T>.error(
    UnsupportedError('This adapter only exposes Matrix room creation.'),
  );
}

final class MatrixDirectRoomMetadataPort implements DirectRoomMetadataPort {
  const MatrixDirectRoomMetadataPort();

  @override
  Future<void> replaceDirectRoomMapping({
    required String roomId,
    required Set<String> userIds,
  }) async {}
}
