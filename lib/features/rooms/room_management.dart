enum KiteRoomCreationKind { directMessage, privateRoom, publicRoom, space }

enum KiteRoomJoinRule { invite, public, knock, restricted }

enum KiteRoomHistoryVisibility { invited, joined, shared, worldReadable }

enum KiteRoomNotificationMode { allMessages, mentionsOnly, mute }

final class KiteRoomCapabilities {
  KiteRoomCapabilities({
    required this.canCreatePublicRooms,
    required Set<KiteRoomJoinRule> supportedJoinRules,
  }) : supportedJoinRules = Set<KiteRoomJoinRule>.unmodifiable(
         supportedJoinRules,
       );

  const KiteRoomCapabilities.privateOnly()
    : canCreatePublicRooms = false,
      supportedJoinRules = const <KiteRoomJoinRule>{KiteRoomJoinRule.invite};

  final bool canCreatePublicRooms;
  final Set<KiteRoomJoinRule> supportedJoinRules;

  bool supports(KiteRoomJoinRule rule) => supportedJoinRules.contains(rule);
}

final class KiteRoomCreationRequest {
  KiteRoomCreationRequest({
    required this.kind,
    required this.name,
    required this.topic,
    required Iterable<String> invitees,
    required this.joinRule,
    required this.encryptionEnabled,
    required this.historyVisibility,
    required this.canonicalAlias,
    required this.parentSpaceId,
  }) : invitees = List<String>.unmodifiable(invitees);

  final KiteRoomCreationKind kind;
  final String? name;
  final String? topic;
  final List<String> invitees;
  final KiteRoomJoinRule joinRule;
  final bool encryptionEnabled;
  final KiteRoomHistoryVisibility historyVisibility;
  final String? canonicalAlias;
  final String? parentSpaceId;
}

final class KiteCreatedRoom {
  const KiteCreatedRoom({
    required this.roomId,
    required this.isDirect,
    required this.displayName,
  });

  final String roomId;
  final bool isDirect;
  final String displayName;
}

final class KiteUserSearchResult {
  const KiteUserSearchResult({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String? displayName;
  final Uri? avatarUrl;
}

final class KiteRoomDirectoryResult {
  const KiteRoomDirectoryResult({
    required this.roomId,
    required this.name,
    required this.topic,
    required this.canonicalAlias,
    required this.avatarUrl,
    required this.joinRule,
    required this.worldReadable,
    required this.joinedMembers,
  });

  final String roomId;
  final String? name;
  final String? topic;
  final String? canonicalAlias;
  final Uri? avatarUrl;
  final String joinRule;
  final bool worldReadable;
  final int joinedMembers;
}

final class KiteSpaceHierarchyEntry {
  KiteSpaceHierarchyEntry({
    required this.roomId,
    required this.name,
    required this.topic,
    required this.canonicalAlias,
    required this.avatarUrl,
    required this.joinRule,
    required this.worldReadable,
    required this.joinedMembers,
    required this.isSpace,
    required Iterable<String> childRoomIds,
  }) : childRoomIds = List<String>.unmodifiable(childRoomIds);

  final String roomId;
  final String? name;
  final String? topic;
  final String? canonicalAlias;
  final Uri? avatarUrl;
  final String joinRule;
  final bool worldReadable;
  final int joinedMembers;
  final bool isSpace;
  final List<String> childRoomIds;
}

final class KiteRoomDetails {
  KiteRoomDetails({
    required this.roomId,
    required this.name,
    required this.topic,
    required this.avatarUrl,
    required this.canonicalAlias,
    required this.joinRule,
    required this.encryptionEnabled,
    required this.historyVisibility,
    required this.notificationMode,
    required this.isDirect,
    required Iterable<String> directUserIds,
  }) : directUserIds = Set<String>.unmodifiable(directUserIds);

  final String roomId;
  final String? name;
  final String? topic;
  final Uri? avatarUrl;
  final String? canonicalAlias;
  final KiteRoomJoinRule joinRule;
  final bool encryptionEnabled;
  final KiteRoomHistoryVisibility historyVisibility;
  final KiteRoomNotificationMode notificationMode;
  final bool isDirect;
  final Set<String> directUserIds;
}

abstract interface class RoomUserSearchPort {
  Future<List<KiteUserSearchResult>> searchUsers(String query);
}

abstract interface class RoomDirectorySearchPort {
  Future<List<KiteRoomDirectoryResult>> searchRoomDirectory(String query);
}

abstract interface class RoomDirectoryMembershipPort {
  Future<void> joinRoomFromDirectory(String roomId);
  Future<void> requestRoomJoin(String roomId);
}

abstract interface class RoomSpaceHierarchyPort {
  Future<List<KiteSpaceHierarchyEntry>> loadSpaceHierarchy(String spaceId);
}

abstract interface class DirectMessageOpenPort {
  Future<KiteCreatedRoom> openDirectMessage(String userId);
}

abstract interface class RoomManagementPort {
  Future<KiteRoomCapabilities> capabilities();

  Future<KiteCreatedRoom> createRoom(KiteRoomCreationRequest request);

  Future<void> setSpaceChild({
    required String spaceId,
    required String roomId,
    required bool linked,
  });

  Future<KiteRoomDetails> roomDetails(String roomId);

  Future<void> setName({required String roomId, required String? name});

  Future<void> setTopic({required String roomId, required String? topic});

  Future<void> setAvatar({required String roomId, required Uri? avatarUrl});

  Future<void> setCanonicalAlias({
    required String roomId,
    required String? canonicalAlias,
  });

  Future<void> setJoinRule({
    required String roomId,
    required KiteRoomJoinRule joinRule,
  });

  Future<void> enableEncryption(String roomId);

  Future<void> setHistoryVisibility({
    required String roomId,
    required KiteRoomHistoryVisibility visibility,
  });

  Future<void> setNotificationMode({
    required String roomId,
    required KiteRoomNotificationMode mode,
  });

  Future<void> reportRoom({required String roomId, String? reason});

  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  });

  Future<void> leaveRoom(String roomId);

  Future<void> forgetRoom(String roomId);
}

final class KiteRoomAvatarSelection {
  const KiteRoomAvatarSelection(this.avatarUrl);

  const KiteRoomAvatarSelection.remove() : avatarUrl = null;

  final Uri? avatarUrl;
}

abstract interface class RoomAvatarMediaPort {
  Future<KiteRoomAvatarSelection?> chooseAndUploadAvatar({
    required String roomId,
    required Uri? currentAvatarUrl,
  });
}

abstract interface class DirectRoomMetadataPort {
  Future<void> replaceDirectRoomMapping({
    required String roomId,
    required Set<String> userIds,
  });
}

final class RoomManagementValidationException implements Exception {
  const RoomManagementValidationException(this.message);

  final String message;

  @override
  String toString() => 'RoomManagementValidationException($message)';
}

final class RoomManagementCoordinator {
  factory RoomManagementCoordinator({
    required RoomManagementPort rooms,
    required DirectRoomMetadataPort directMetadata,
  }) => RoomManagementCoordinator._(rooms, directMetadata);

  const RoomManagementCoordinator._(this._rooms, this._directMetadata);

  final RoomManagementPort _rooms;
  final DirectRoomMetadataPort _directMetadata;

  Future<KiteRoomCapabilities> capabilities() => _rooms.capabilities();

  Future<List<KiteUserSearchResult>> searchUsers(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2 || _rooms is! RoomUserSearchPort) {
      return const <KiteUserSearchResult>[];
    }
    return (_rooms as RoomUserSearchPort).searchUsers(query);
  }

  Future<List<KiteSpaceHierarchyEntry>> loadSpaceHierarchy(
    String spaceId,
  ) async {
    final rooms = _rooms;
    if (rooms is! RoomSpaceHierarchyPort) {
      return const <KiteSpaceHierarchyEntry>[];
    }
    return (rooms as RoomSpaceHierarchyPort).loadSpaceHierarchy(
      _roomId(spaceId),
    );
  }

  Future<List<KiteRoomDirectoryResult>> searchRoomDirectory(
    String rawQuery,
  ) async {
    final rooms = _rooms;
    if (rooms is! RoomDirectorySearchPort) {
      return const <KiteRoomDirectoryResult>[];
    }
    return (rooms as RoomDirectorySearchPort).searchRoomDirectory(
      rawQuery.trim(),
    );
  }

  Future<void> joinRoomFromDirectory(String roomId) async {
    final rooms = _rooms;
    if (rooms is! RoomDirectoryMembershipPort) {
      throw const RoomManagementValidationException(
        'Room directory membership is unavailable.',
      );
    }
    await (rooms as RoomDirectoryMembershipPort).joinRoomFromDirectory(
      _roomId(roomId),
    );
  }

  Future<void> requestRoomJoin(String roomId) async {
    final rooms = _rooms;
    if (rooms is! RoomDirectoryMembershipPort) {
      throw const RoomManagementValidationException(
        'Room directory membership is unavailable.',
      );
    }
    await (rooms as RoomDirectoryMembershipPort).requestRoomJoin(
      _roomId(roomId),
    );
  }

  Future<KiteCreatedRoom> openDirectMessage(String rawUserId) async {
    final userId = _matrixUserId(rawUserId);
    final rooms = _rooms;
    if (rooms is DirectMessageOpenPort) {
      final opened = await (rooms as DirectMessageOpenPort).openDirectMessage(
        userId,
      );
      final roomId = _roomId(opened.roomId);
      await _directMetadata.replaceDirectRoomMapping(
        roomId: roomId,
        userIds: <String>{userId},
      );
      return KiteCreatedRoom(
        roomId: roomId,
        isDirect: true,
        displayName: opened.displayName,
      );
    }
    return createDirectMessage(userId);
  }

  Future<KiteCreatedRoom> createDirectMessage(String rawUserId) async {
    final userId = _matrixUserId(rawUserId);
    final created = await _rooms.createRoom(
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
    await _directMetadata.replaceDirectRoomMapping(
      roomId: created.roomId,
      userIds: <String>{userId},
    );
    return created;
  }

  Future<KiteCreatedRoom> createPrivateRoom({
    required String name,
    String? topic,
    Iterable<String> invitees = const <String>[],
    KiteRoomJoinRule joinRule = KiteRoomJoinRule.invite,
    bool encryptionEnabled = true,
    KiteRoomHistoryVisibility historyVisibility =
        KiteRoomHistoryVisibility.joined,
    String? parentSpaceId,
  }) async {
    if (joinRule == KiteRoomJoinRule.public) {
      throw const RoomManagementValidationException(
        'Private rooms cannot use the public join rule.',
      );
    }
    await _requireJoinRule(joinRule);
    return _rooms.createRoom(
      KiteRoomCreationRequest(
        kind: KiteRoomCreationKind.privateRoom,
        name: _requiredName(name),
        topic: _optionalText(topic),
        invitees: _matrixUserIds(invitees),
        joinRule: joinRule,
        encryptionEnabled: encryptionEnabled,
        historyVisibility: historyVisibility,
        canonicalAlias: null,
        parentSpaceId: _optionalRoomId(parentSpaceId),
      ),
    );
  }

  Future<KiteCreatedRoom> createPublicRoom({
    required String name,
    String? topic,
    String? canonicalAlias,
    bool encryptionEnabled = false,
    KiteRoomHistoryVisibility historyVisibility =
        KiteRoomHistoryVisibility.shared,
    String? parentSpaceId,
  }) async {
    final capabilities = await _rooms.capabilities();
    if (!capabilities.canCreatePublicRooms ||
        !capabilities.supports(KiteRoomJoinRule.public)) {
      throw const RoomManagementValidationException(
        'The homeserver does not allow public room creation.',
      );
    }
    return _rooms.createRoom(
      KiteRoomCreationRequest(
        kind: KiteRoomCreationKind.publicRoom,
        name: _requiredName(name),
        topic: _optionalText(topic),
        invitees: const <String>[],
        joinRule: KiteRoomJoinRule.public,
        encryptionEnabled: encryptionEnabled,
        historyVisibility: historyVisibility,
        canonicalAlias: _canonicalAlias(canonicalAlias),
        parentSpaceId: _optionalRoomId(parentSpaceId),
      ),
    );
  }

  Future<KiteCreatedRoom> createSpace({
    required String name,
    String? topic,
    bool isPublic = false,
  }) async {
    if (isPublic) {
      final capabilities = await _rooms.capabilities();
      if (!capabilities.canCreatePublicRooms ||
          !capabilities.supports(KiteRoomJoinRule.public)) {
        throw const RoomManagementValidationException(
          'The homeserver does not allow public Space creation.',
        );
      }
    }
    return _rooms.createRoom(
      KiteRoomCreationRequest(
        kind: KiteRoomCreationKind.space,
        name: _requiredName(name),
        topic: _optionalText(topic),
        invitees: const <String>[],
        joinRule: isPublic ? KiteRoomJoinRule.public : KiteRoomJoinRule.invite,
        encryptionEnabled: false,
        historyVisibility: KiteRoomHistoryVisibility.shared,
        canonicalAlias: null,
        parentSpaceId: null,
      ),
    );
  }

  Future<void> setSpaceChild({
    required String spaceId,
    required String roomId,
    required bool linked,
  }) {
    final normalizedSpaceId = _roomId(spaceId);
    final normalizedRoomId = _roomId(roomId);
    if (normalizedSpaceId == normalizedRoomId) {
      throw const RoomManagementValidationException(
        'A Matrix Space cannot contain itself.',
      );
    }
    return _rooms.setSpaceChild(
      spaceId: normalizedSpaceId,
      roomId: normalizedRoomId,
      linked: linked,
    );
  }

  Future<KiteRoomDetails> roomDetails(String rawRoomId) async {
    final details = await _rooms.roomDetails(_roomId(rawRoomId));
    await reconcileDirectMetadata(details);
    return details;
  }

  Future<void> setName({required String roomId, required String? name}) =>
      _rooms.setName(
        roomId: _roomId(roomId),
        name: name == null ? null : _requiredName(name),
      );

  Future<void> setTopic({required String roomId, required String? topic}) =>
      _rooms.setTopic(roomId: _roomId(roomId), topic: _optionalText(topic));

  Future<void> setAvatar({required String roomId, required Uri? avatarUrl}) {
    if (avatarUrl != null && avatarUrl.scheme != 'mxc') {
      throw const RoomManagementValidationException(
        'Room avatars must use an mxc URI supplied by the Matrix SDK.',
      );
    }
    return _rooms.setAvatar(roomId: _roomId(roomId), avatarUrl: avatarUrl);
  }

  Future<void> setCanonicalAlias({
    required String roomId,
    required String? canonicalAlias,
  }) => _rooms.setCanonicalAlias(
    roomId: _roomId(roomId),
    canonicalAlias: _canonicalAlias(canonicalAlias),
  );

  Future<void> setJoinRule({
    required String roomId,
    required KiteRoomJoinRule joinRule,
  }) async {
    await _requireJoinRule(joinRule);
    await _rooms.setJoinRule(roomId: _roomId(roomId), joinRule: joinRule);
  }

  Future<void> enableEncryption(String roomId) =>
      _rooms.enableEncryption(_roomId(roomId));

  Future<void> setHistoryVisibility({
    required String roomId,
    required KiteRoomHistoryVisibility visibility,
  }) => _rooms.setHistoryVisibility(
    roomId: _roomId(roomId),
    visibility: visibility,
  );

  Future<void> setNotificationMode({
    required String roomId,
    required KiteRoomNotificationMode mode,
  }) => _rooms.setNotificationMode(roomId: _roomId(roomId), mode: mode);

  Future<void> reportRoom({required String roomId, String? reason}) =>
      _rooms.reportRoom(roomId: _roomId(roomId), reason: _optionalText(reason));

  Future<void> reportUser({
    required String roomId,
    required String userId,
    String? reason,
  }) => _rooms.reportUser(
    roomId: _roomId(roomId),
    userId: _matrixUserId(userId),
    reason: _optionalText(reason),
  );

  Future<void> leaveRoom(String roomId) async {
    final normalizedRoomId = _roomId(roomId);
    await _rooms.leaveRoom(normalizedRoomId);
    await _directMetadata.replaceDirectRoomMapping(
      roomId: normalizedRoomId,
      userIds: const <String>{},
    );
  }

  Future<void> forgetRoom(String roomId) async {
    final normalizedRoomId = _roomId(roomId);
    await _rooms.forgetRoom(normalizedRoomId);
    await _directMetadata.replaceDirectRoomMapping(
      roomId: normalizedRoomId,
      userIds: const <String>{},
    );
  }

  Future<void> reconcileDirectMetadata(KiteRoomDetails details) async {
    await _directMetadata.replaceDirectRoomMapping(
      roomId: _roomId(details.roomId),
      userIds: details.isDirect
          ? Set<String>.unmodifiable(details.directUserIds.map(_matrixUserId))
          : const <String>{},
    );
  }

  Future<void> _requireJoinRule(KiteRoomJoinRule rule) async {
    final capabilities = await _rooms.capabilities();
    if (!capabilities.supports(rule)) {
      throw RoomManagementValidationException(
        'The homeserver does not support the ${rule.name} join rule.',
      );
    }
  }

  String _requiredName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const RoomManagementValidationException('Room name is required.');
    }
    return normalized;
  }

  String _matrixUserId(String value) {
    final normalized = value.trim();
    if (!normalized.startsWith('@') ||
        !normalized.contains(':') ||
        normalized.contains(RegExp(r'\s'))) {
      throw const RoomManagementValidationException(
        'A valid Matrix user ID is required.',
      );
    }
    return normalized;
  }

  List<String> _matrixUserIds(Iterable<String> values) =>
      List<String>.unmodifiable(values.map(_matrixUserId).toSet());

  String _roomId(String value) {
    final normalized = value.trim();
    if (!normalized.startsWith('!') ||
        !normalized.contains(':') ||
        normalized.contains(RegExp(r'\s'))) {
      throw const RoomManagementValidationException(
        'A valid Matrix room ID is required.',
      );
    }
    return normalized;
  }

  String? _optionalRoomId(String? value) {
    final normalized = _optionalText(value);
    return normalized == null ? null : _roomId(normalized);
  }

  String? _canonicalAlias(String? value) {
    final normalized = _optionalText(value);
    if (normalized == null) return null;
    if (!normalized.startsWith('#') ||
        !normalized.contains(':') ||
        normalized.contains(RegExp(r'\s'))) {
      throw const RoomManagementValidationException(
        'A canonical room alias must look like #room:server.',
      );
    }
    return normalized;
  }

  String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
