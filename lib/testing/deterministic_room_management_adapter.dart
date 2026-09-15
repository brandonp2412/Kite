import 'package:kite/features/rooms/room_management.dart';

enum RoomManagementInvocationType {
  capabilities,
  create,
  details,
  setName,
  setTopic,
  setAvatar,
  setCanonicalAlias,
  setJoinRule,
  enableEncryption,
  setHistoryVisibility,
  setNotificationMode,
}

final class RoomManagementInvocation {
  const RoomManagementInvocation({
    required this.type,
    this.roomId,
    this.creation,
    this.text,
    this.avatarUrl,
    this.joinRule,
    this.historyVisibility,
    this.notificationMode,
  });

  final RoomManagementInvocationType type;
  final String? roomId;
  final KiteRoomCreationRequest? creation;
  final String? text;
  final Uri? avatarUrl;
  final KiteRoomJoinRule? joinRule;
  final KiteRoomHistoryVisibility? historyVisibility;
  final KiteRoomNotificationMode? notificationMode;
}

final class DeterministicRoomManagementPort implements RoomManagementPort {
  DeterministicRoomManagementPort({
    this.seed = 0,
    KiteRoomCapabilities? roomCapabilities,
  }) : roomCapabilities =
           roomCapabilities ??
           KiteRoomCapabilities(
             canCreatePublicRooms: true,
             supportedJoinRules: KiteRoomJoinRule.values.toSet(),
           );

  final int seed;
  KiteRoomCapabilities roomCapabilities;
  final List<RoomManagementInvocation> invocations =
      <RoomManagementInvocation>[];
  final Map<String, KiteRoomDetails> detailsByRoomId =
      <String, KiteRoomDetails>{};
  Object? failNextWith;
  int _roomCounter = 0;

  @override
  Future<KiteRoomCapabilities> capabilities() async {
    invocations.add(
      const RoomManagementInvocation(
        type: RoomManagementInvocationType.capabilities,
      ),
    );
    _throwIfRequested();
    return roomCapabilities;
  }

  @override
  Future<KiteCreatedRoom> createRoom(KiteRoomCreationRequest request) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.create,
        creation: request,
      ),
    );
    _throwIfRequested();
    _roomCounter += 1;
    final roomId = '!room${seed + _roomCounter}:example.org';
    final isDirect = request.kind == KiteRoomCreationKind.directMessage;
    detailsByRoomId[roomId] = KiteRoomDetails(
      roomId: roomId,
      name: request.name,
      topic: request.topic,
      avatarUrl: null,
      canonicalAlias: request.canonicalAlias,
      joinRule: request.joinRule,
      encryptionEnabled: request.encryptionEnabled,
      historyVisibility: request.historyVisibility,
      notificationMode: KiteRoomNotificationMode.allMessages,
      isDirect: isDirect,
      directUserIds: isDirect ? request.invitees : const <String>[],
    );
    return KiteCreatedRoom(roomId: roomId, isDirect: isDirect);
  }

  @override
  Future<KiteRoomDetails> roomDetails(String roomId) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.details,
        roomId: roomId,
      ),
    );
    _throwIfRequested();
    final details = detailsByRoomId[roomId];
    if (details == null) throw StateError('Unknown room $roomId');
    return details;
  }

  @override
  Future<void> setName({required String roomId, required String? name}) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setName,
        roomId: roomId,
        text: name,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setTopic({
    required String roomId,
    required String? topic,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setTopic,
        roomId: roomId,
        text: topic,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setAvatar({
    required String roomId,
    required Uri? avatarUrl,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setAvatar,
        roomId: roomId,
        avatarUrl: avatarUrl,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setCanonicalAlias({
    required String roomId,
    required String? canonicalAlias,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setCanonicalAlias,
        roomId: roomId,
        text: canonicalAlias,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setJoinRule({
    required String roomId,
    required KiteRoomJoinRule joinRule,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setJoinRule,
        roomId: roomId,
        joinRule: joinRule,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> enableEncryption(String roomId) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.enableEncryption,
        roomId: roomId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setHistoryVisibility({
    required String roomId,
    required KiteRoomHistoryVisibility visibility,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setHistoryVisibility,
        roomId: roomId,
        historyVisibility: visibility,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setNotificationMode({
    required String roomId,
    required KiteRoomNotificationMode mode,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.setNotificationMode,
        roomId: roomId,
        notificationMode: mode,
      ),
    );
    _throwIfRequested();
  }

  void _throwIfRequested() {
    final error = failNextWith;
    failNextWith = null;
    if (error != null) throw error;
  }
}

final class DirectRoomMappingInvocation {
  DirectRoomMappingInvocation({
    required this.roomId,
    required Set<String> userIds,
  }) : userIds = Set<String>.unmodifiable(userIds);

  final String roomId;
  final Set<String> userIds;
}

final class DeterministicDirectRoomMetadataPort
    implements DirectRoomMetadataPort {
  final List<DirectRoomMappingInvocation> invocations =
      <DirectRoomMappingInvocation>[];
  Object? failNextWith;

  @override
  Future<void> replaceDirectRoomMapping({
    required String roomId,
    required Set<String> userIds,
  }) async {
    final error = failNextWith;
    failNextWith = null;
    if (error != null) throw error;
    invocations.add(
      DirectRoomMappingInvocation(roomId: roomId, userIds: userIds),
    );
  }
}
