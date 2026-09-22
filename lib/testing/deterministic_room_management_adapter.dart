import 'package:kite/features/rooms/room_management.dart';

enum RoomManagementInvocationType {
  capabilities,
  searchUsers,
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
  reportRoom,
  reportUser,
  leaveRoom,
  forgetRoom,
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
    this.userId,
    this.reason,
  });

  final RoomManagementInvocationType type;
  final String? roomId;
  final KiteRoomCreationRequest? creation;
  final String? text;
  final Uri? avatarUrl;
  final KiteRoomJoinRule? joinRule;
  final KiteRoomHistoryVisibility? historyVisibility;
  final KiteRoomNotificationMode? notificationMode;
  final String? userId;
  final String? reason;
}

final class DeterministicRoomManagementPort
    implements RoomManagementPort, RoomUserSearchPort {
  DeterministicRoomManagementPort({
    this.seed = 0,
    KiteRoomCapabilities? roomCapabilities,
    Iterable<KiteUserSearchResult> userSearchResults =
        const <KiteUserSearchResult>[],
  }) : roomCapabilities =
           roomCapabilities ??
           KiteRoomCapabilities(
             canCreatePublicRooms: true,
             supportedJoinRules: KiteRoomJoinRule.values.toSet(),
           ),
       userSearchResults = List<KiteUserSearchResult>.unmodifiable(
         userSearchResults,
       );

  final int seed;
  KiteRoomCapabilities roomCapabilities;
  final List<KiteUserSearchResult> userSearchResults;
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
  Future<List<KiteUserSearchResult>> searchUsers(String query) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.searchUsers,
        text: query,
      ),
    );
    _throwIfRequested();
    final normalized = query.trim().toLowerCase();
    return <KiteUserSearchResult>[
      for (final result in userSearchResults)
        if (result.userId.toLowerCase().contains(normalized) ||
            (result.displayName?.toLowerCase().contains(normalized) ?? false))
          result,
    ];
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
    return KiteCreatedRoom(
      roomId: roomId,
      isDirect: isDirect,
      displayName: request.name ?? (request.invitees.length == 1 ? request.invitees.single : roomId),
    );
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

  @override
  Future<void> reportRoom({required String roomId, String? reason}) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.reportRoom,
        roomId: roomId,
        reason: reason,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.reportUser,
        roomId: roomId,
        userId: userId,
        reason: reason,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.leaveRoom,
        roomId: roomId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> forgetRoom(String roomId) async {
    invocations.add(
      RoomManagementInvocation(
        type: RoomManagementInvocationType.forgetRoom,
        roomId: roomId,
      ),
    );
    _throwIfRequested();
    detailsByRoomId.remove(roomId);
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

final class RoomAvatarMediaInvocation {
  const RoomAvatarMediaInvocation({
    required this.roomId,
    required this.currentAvatarUrl,
  });

  final String roomId;
  final Uri? currentAvatarUrl;
}

final class DeterministicRoomAvatarMediaPort implements RoomAvatarMediaPort {
  DeterministicRoomAvatarMediaPort({this.nextSelection});

  KiteRoomAvatarSelection? nextSelection;
  Object? failNextWith;
  final List<RoomAvatarMediaInvocation> invocations =
      <RoomAvatarMediaInvocation>[];

  @override
  Future<KiteRoomAvatarSelection?> chooseAndUploadAvatar({
    required String roomId,
    required Uri? currentAvatarUrl,
  }) async {
    invocations.add(
      RoomAvatarMediaInvocation(
        roomId: roomId,
        currentAvatarUrl: currentAvatarUrl,
      ),
    );
    final error = failNextWith;
    failNextWith = null;
    if (error != null) throw error;
    return nextSelection;
  }
}
