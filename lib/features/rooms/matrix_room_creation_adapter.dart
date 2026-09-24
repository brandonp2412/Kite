import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

typedef MatrixRoomCreate = Future<MatrixSdkCreatedRoom> Function(
  MatrixSdkRoomCreationRequest request,
);
typedef MatrixDirectMessageOpen = Future<String> Function(String userId);
typedef MatrixRoomReport = Future<void> Function(String roomId, String? reason);
typedef MatrixUserReport = Future<void> Function(
  String roomId,
  String userId,
  String? reason,
);
typedef MatrixRoomMutation = Future<void> Function(String roomId);
typedef MatrixSpaceChildMutation = Future<void> Function(
  String spaceId,
  String roomId,
  bool linked,
);
typedef MatrixRoomDetailsLookup = Future<MatrixSdkRoomDetails> Function(
  String roomId,
);
typedef MatrixRoomTextMutation = Future<void> Function(
  String roomId,
  String? value,
);
typedef MatrixRoomRequiredTextMutation = Future<void> Function(
  String roomId,
  String value,
);
typedef MatrixUserSearch = Future<List<MatrixSdkUserSearchResult>> Function(
  String query,
);
typedef MatrixRoomDirectorySearch =
    Future<List<MatrixSdkRoomDirectoryResult>> Function(String query);

final class MatrixRoomCreationManagementPort
    implements
        RoomManagementPort,
        RoomUserSearchPort,
        RoomDirectorySearchPort,
        RoomDirectoryMembershipPort,
        DirectMessageOpenPort {
  const MatrixRoomCreationManagementPort(
    this._create, {
    required MatrixRoomReport reportRoom,
    required MatrixUserReport reportUser,
    required MatrixRoomMutation leaveRoom,
    required MatrixRoomMutation forgetRoom,
    required MatrixRoomDetailsLookup roomDetails,
    required MatrixRoomTextMutation setName,
    required MatrixRoomTextMutation setTopic,
    required MatrixRoomTextMutation setAvatar,
    required MatrixRoomTextMutation setCanonicalAlias,
    required MatrixRoomRequiredTextMutation setJoinRule,
    required MatrixRoomMutation enableEncryption,
    required MatrixRoomRequiredTextMutation setHistoryVisibility,
    required MatrixRoomRequiredTextMutation setNotificationMode,
    this.userSearch,
    this.roomDirectorySearch,
    this.directoryJoin,
    this.directoryKnock,
    this.directMessageOpen,
    this.spaceChildMutation,
  }) : _lifecycle = (
         reportRoom: reportRoom,
         reportUser: reportUser,
         leaveRoom: leaveRoom,
         forgetRoom: forgetRoom,
       ),
       _settings = (
         roomDetails: roomDetails,
         setName: setName,
         setTopic: setTopic,
         setAvatar: setAvatar,
         setCanonicalAlias: setCanonicalAlias,
         setJoinRule: setJoinRule,
         enableEncryption: enableEncryption,
         setHistoryVisibility: setHistoryVisibility,
         setNotificationMode: setNotificationMode,
       );

  final MatrixRoomCreate _create;
  final MatrixUserSearch? userSearch;
  final MatrixRoomDirectorySearch? roomDirectorySearch;
  final MatrixRoomMutation? directoryJoin;
  final MatrixRoomMutation? directoryKnock;
  final MatrixDirectMessageOpen? directMessageOpen;
  final MatrixSpaceChildMutation? spaceChildMutation;
  final ({
    MatrixRoomReport reportRoom,
    MatrixUserReport reportUser,
    MatrixRoomMutation leaveRoom,
    MatrixRoomMutation forgetRoom,
  })
  _lifecycle;
  final ({
    MatrixRoomDetailsLookup roomDetails,
    MatrixRoomTextMutation setName,
    MatrixRoomTextMutation setTopic,
    MatrixRoomTextMutation setAvatar,
    MatrixRoomTextMutation setCanonicalAlias,
    MatrixRoomRequiredTextMutation setJoinRule,
    MatrixRoomMutation enableEncryption,
    MatrixRoomRequiredTextMutation setHistoryVisibility,
    MatrixRoomRequiredTextMutation setNotificationMode,
  })
  _settings;

  @override
  Future<KiteRoomCapabilities> capabilities() async => KiteRoomCapabilities(
    canCreatePublicRooms: true,
    supportedJoinRules: const <KiteRoomJoinRule>{
      KiteRoomJoinRule.invite,
      KiteRoomJoinRule.public,
    },
  );

  @override
  Future<List<KiteUserSearchResult>> searchUsers(String query) async {
    final search = userSearch;
    if (search == null) return const <KiteUserSearchResult>[];
    final results = await search(query);
    return <KiteUserSearchResult>[
      for (final result in results)
        KiteUserSearchResult(
          userId: result.userId,
          displayName: result.displayName,
          avatarUrl: result.avatarUrl == null
              ? null
              : Uri.parse(result.avatarUrl!),
        ),
    ];
  }

  @override
  Future<List<KiteRoomDirectoryResult>> searchRoomDirectory(
    String query,
  ) async {
    final search = roomDirectorySearch;
    if (search == null) return const <KiteRoomDirectoryResult>[];
    final results = await search(query);
    return <KiteRoomDirectoryResult>[
      for (final result in results)
        KiteRoomDirectoryResult(
          roomId: result.roomId,
          name: result.name,
          topic: result.topic,
          canonicalAlias: result.canonicalAlias,
          avatarUrl: result.avatarUrl == null
              ? null
              : Uri.parse(result.avatarUrl!),
          joinRule: result.joinRule,
          worldReadable: result.worldReadable,
          joinedMembers: result.joinedMembers,
        ),
    ];
  }

  @override
  Future<void> joinRoomFromDirectory(String roomId) {
    final join = directoryJoin;
    if (join == null) {
      throw StateError('Matrix room directory joining is unavailable.');
    }
    return join(roomId);
  }

  @override
  Future<void> requestRoomJoin(String roomId) {
    final knock = directoryKnock;
    if (knock == null) {
      throw StateError('Matrix room join requests are unavailable.');
    }
    return knock(roomId);
  }

  @override
  Future<KiteCreatedRoom> openDirectMessage(String userId) async {
    final open = directMessageOpen;
    if (open == null) {
      return createRoom(
        KiteRoomCreationRequest(
          kind: KiteRoomCreationKind.directMessage,
          name: null,
          topic: null,
          invitees: <String>[userId],
          joinRule: KiteRoomJoinRule.invite,
          encryptionEnabled: true,
          historyVisibility: KiteRoomHistoryVisibility.joined,
          canonicalAlias: null,
          parentSpaceId: null,
        ),
      );
    }
    final roomId = await open(userId);
    return KiteCreatedRoom(roomId: roomId, isDirect: true, displayName: userId);
  }

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
          KiteRoomCreationKind.space => MatrixSdkRoomCreationKind.space,
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
    return KiteCreatedRoom(
      roomId: created.roomId,
      isDirect: created.isDirect,
      displayName:
          request.name ??
          (request.invitees.length == 1
              ? request.invitees.single
              : created.roomId),
    );
  }

  @override
  Future<void> setSpaceChild({
    required String spaceId,
    required String roomId,
    required bool linked,
  }) {
    final mutate = spaceChildMutation;
    if (mutate == null) {
      throw StateError('Matrix Space child mutations are unavailable.');
    }
    return mutate(spaceId, roomId, linked);
  }

  @override
  Future<KiteRoomDetails> roomDetails(String roomId) async {
    final details = await _settings.roomDetails(roomId);
    return KiteRoomDetails(
      roomId: details.roomId,
      name: details.name,
      topic: details.topic,
      avatarUrl: details.avatarUrl == null
          ? null
          : Uri.parse(details.avatarUrl!),
      canonicalAlias: details.canonicalAlias,
      joinRule: KiteRoomJoinRule.values.byName(details.joinRule),
      encryptionEnabled: details.encryptionEnabled,
      historyVisibility: KiteRoomHistoryVisibility.values.byName(
        details.historyVisibility,
      ),
      notificationMode: KiteRoomNotificationMode.values.byName(
        details.notificationMode,
      ),
      isDirect: details.isDirect,
      directUserIds: details.directUserIds,
    );
  }

  @override
  Future<void> setName({required String roomId, required String? name}) =>
      _settings.setName(roomId, name);

  @override
  Future<void> setTopic({required String roomId, required String? topic}) =>
      _settings.setTopic(roomId, topic);

  @override
  Future<void> setAvatar({required String roomId, required Uri? avatarUrl}) =>
      _settings.setAvatar(roomId, avatarUrl?.toString());

  @override
  Future<void> setCanonicalAlias({
    required String roomId,
    required String? canonicalAlias,
  }) => _settings.setCanonicalAlias(roomId, canonicalAlias);

  @override
  Future<void> setJoinRule({
    required String roomId,
    required KiteRoomJoinRule joinRule,
  }) => _settings.setJoinRule(roomId, joinRule.name);

  @override
  Future<void> enableEncryption(String roomId) =>
      _settings.enableEncryption(roomId);

  @override
  Future<void> setHistoryVisibility({
    required String roomId,
    required KiteRoomHistoryVisibility visibility,
  }) => _settings.setHistoryVisibility(roomId, visibility.name);

  @override
  Future<void> setNotificationMode({
    required String roomId,
    required KiteRoomNotificationMode mode,
  }) => _settings.setNotificationMode(roomId, mode.name);

  @override
  Future<void> reportRoom({required String roomId, String? reason}) =>
      _lifecycle.reportRoom(roomId, reason);

  @override
  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) => _lifecycle.reportUser(roomId, userId, reason);

  @override
  Future<void> leaveRoom(String roomId) => _lifecycle.leaveRoom(roomId);

  @override
  Future<void> forgetRoom(String roomId) => _lifecycle.forgetRoom(roomId);
}

final class MatrixDirectRoomMetadataPort implements DirectRoomMetadataPort {
  const MatrixDirectRoomMetadataPort();

  @override
  Future<void> replaceDirectRoomMapping({
    required String roomId,
    required Set<String> userIds,
  }) async {}
}
