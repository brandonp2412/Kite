import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';

enum MatrixSdkCapability {
  auditedEncryption,
  encryptedPersistentStore,
  incrementalSync,
  backPagination,
}

final class MatrixSdkStoreConfiguration {
  const MatrixSdkStoreConfiguration({
    required this.accountId,
    required this.storePath,
    required this.encryptionKeyId,
  });

  final String accountId;
  final String storePath;
  final String encryptionKeyId;
}

final class MatrixSdkSyncConfiguration {
  const MatrixSdkSyncConfiguration({
    this.initialRoomListLimit = 200,
    this.initialTimelineEventLimit = 1,
    this.timelineEventLimit = 20,
    this.resumeFromCursor,
  }) : assert(initialRoomListLimit > 0),
       assert(initialTimelineEventLimit > 0),
       assert(initialTimelineEventLimit <= timelineEventLimit),
       assert(timelineEventLimit > 0);

  final int initialRoomListLimit;
  final int initialTimelineEventLimit;
  final int timelineEventLimit;
  final String? resumeFromCursor;
}

final class MatrixSdkPasswordLoginResult {
  const MatrixSdkPasswordLoginResult({
    required this.userId,
    required this.deviceId,
  });

  final String userId;
  final String deviceId;
}

final class MatrixSdkRoomMember {
  const MatrixSdkRoomMember({
    required this.userId,
    required this.displayName,
    required this.powerLevel,
  });

  final String userId;
  final String displayName;
  final int powerLevel;
}

enum MatrixSdkRoomCreationKind { directMessage, privateRoom, publicRoom }

final class MatrixSdkRoomCreationRequest {
  MatrixSdkRoomCreationRequest({
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

  final MatrixSdkRoomCreationKind kind;
  final String? name;
  final String? topic;
  final List<String> invitees;
  final String joinRule;
  final bool encryptionEnabled;
  final String historyVisibility;
  final String? canonicalAlias;
  final String? parentSpaceId;
}

final class MatrixSdkCreatedRoom {
  const MatrixSdkCreatedRoom({required this.roomId, required this.isDirect});

  final String roomId;
  final bool isDirect;
}

abstract interface class MatrixSdkRoomCreator {
  Future<MatrixSdkCreatedRoom> createRoom(MatrixSdkRoomCreationRequest request);
}

abstract interface class MatrixSdkRoomLifecycleManager {
  Future<void> reportRoom(String roomId, {String? reason});

  Future<void> reportUser(String roomId, String userId, {String? reason});

  Future<void> leaveRoom(String roomId);

  Future<void> forgetRoom(String roomId);
}

abstract interface class MatrixSdkRoomMemberDirectory {
  Future<List<MatrixSdkRoomMember>> roomMembers(String roomId);
}

enum MatrixSdkRoomMemberAction { invite, changePowerLevel, kick, ban, unban }

abstract interface class MatrixSdkRoomMemberInviter {
  Future<void> inviteRoomMember(String roomId, String userId);
}

abstract interface class MatrixSdkRoomMemberModerator {
  Future<bool> canModerateRoomMember({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
    required MatrixSdkRoomMemberAction action,
    int? requestedPowerLevel,
  });

  Future<void> setRoomMemberPowerLevel(
    String roomId,
    String userId,
    int powerLevel,
  );

  Future<void> kickRoomMember(String roomId, String userId);

  Future<void> banRoomMember(String roomId, String userId, {String? reason});

  Future<void> unbanRoomMember(String roomId, String userId);
}

abstract interface class MatrixSdkRoomFavouriteManager {
  Future<void> setRoomFavourite(String roomId, bool isFavourite);
}

abstract interface class MatrixSdkRoomInviteManager {
  Future<void> respondToRoomInvite(String roomId, bool accept);
}

abstract interface class MatrixSdkRoomReadManager {
  Future<void> markRoomRead(String roomId, String eventId);
}

abstract interface class MatrixSdkPasswordAuthenticator {
  Future<MatrixSdkPasswordLoginResult> loginWithPassword({
    required String username,
    required String password,
  });
}

abstract interface class MatrixSdkTextMessageSender {
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
  });
}

abstract interface class MatrixSdkBoundary {
  Set<MatrixSdkCapability> get capabilities;

  Stream<MatrixSyncBatch> get syncBatches;

  Future<void> open(MatrixSdkStoreConfiguration store);

  Future<void> startSync(MatrixSdkSyncConfiguration configuration);

  Future<void> stopSync();

  Future<MatrixPaginationPage> paginateBackwards(String roomId);

  Future<void> close();
}

final class MatrixSdkContractException implements Exception {
  const MatrixSdkContractException(this.message);

  final String message;

  @override
  String toString() => 'MatrixSdkContractException: $message';
}

final class MatrixBoundaryEngine implements MatrixEngine {
  factory MatrixBoundaryEngine({
    required MatrixSdkBoundary boundary,
    required MatrixSdkStoreConfiguration store,
    MatrixSdkSyncConfiguration Function()? syncConfigurationProvider,
  }) {
    _validateStoreConfiguration(store);
    _requireBoundaryCapability(boundary, MatrixSdkCapability.auditedEncryption);
    _requireBoundaryCapability(
      boundary,
      MatrixSdkCapability.encryptedPersistentStore,
    );
    _requireBoundaryCapability(boundary, MatrixSdkCapability.incrementalSync);
    return MatrixBoundaryEngine._(
      boundary,
      store,
      syncConfigurationProvider ?? () => const MatrixSdkSyncConfiguration(),
    );
  }

  MatrixBoundaryEngine._(
    this._boundary,
    this._store,
    this._syncConfigurationProvider,
  );

  final MatrixSdkBoundary _boundary;
  final MatrixSdkStoreConfiguration _store;
  final MatrixSdkSyncConfiguration Function() _syncConfigurationProvider;

  bool _opened = false;
  bool _started = false;
  bool _needsSyncReset = false;

  bool get hasOpenedStore => _opened;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _boundary.syncBatches;

  @override
  Future<void> start() async {
    if (_started) return;
    final configuration = _syncConfigurationProvider();
    _validateSyncConfiguration(configuration);
    await _ensureOpen();
    if (_needsSyncReset) {
      await _boundary.stopSync();
      _needsSyncReset = false;
    }
    _needsSyncReset = true;
    await _boundary.startSync(configuration);
    _started = true;
    _needsSyncReset = false;
  }

  @override
  Future<void> stop() async {
    if (!_started && !_needsSyncReset) return;
    await _boundary.stopSync();
    _started = false;
    _needsSyncReset = false;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    _requireCapability(MatrixSdkCapability.backPagination);
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    await _ensureOpen();
    return _boundary.paginateBackwards(normalizedRoomId);
  }

  Future<MatrixSdkPasswordLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) async {
    final authenticator = _boundary;
    if (authenticator is! MatrixSdkPasswordAuthenticator) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support password authentication',
      );
    }
    await _ensureOpen();
    return (authenticator as MatrixSdkPasswordAuthenticator).loginWithPassword(
      username: username,
      password: password,
    );
  }

  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
  }) async {
    final sender = _boundary;
    if (sender is! MatrixSdkTextMessageSender) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support text messages',
      );
    }
    await _ensureOpen();
    return (sender as MatrixSdkTextMessageSender).sendTextMessage(
      roomId: roomId,
      transactionId: transactionId,
      body: body,
    );
  }

  Future<MatrixSdkCreatedRoom> createRoom(
    MatrixSdkRoomCreationRequest request,
  ) async {
    final creator = _boundary;
    if (creator is! MatrixSdkRoomCreator) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room creation',
      );
    }
    await _ensureOpen();
    return (creator as MatrixSdkRoomCreator).createRoom(request);
  }

  Future<void> reportRoom(String roomId, {String? reason}) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomLifecycleManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room reporting',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomLifecycleManager).reportRoom(
      roomId,
      reason: reason,
    );
  }

  Future<void> reportUser(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomLifecycleManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support user reporting',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomLifecycleManager).reportUser(
      roomId,
      userId,
      reason: reason,
    );
  }

  Future<void> leaveRoom(String roomId) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomLifecycleManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support leaving rooms',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomLifecycleManager).leaveRoom(roomId);
  }

  Future<void> forgetRoom(String roomId) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomLifecycleManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support forgetting rooms',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomLifecycleManager).forgetRoom(roomId);
  }

  Future<void> setRoomFavourite(String roomId, bool isFavourite) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomFavouriteManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room favourites',
      );
    }
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomFavouriteManager).setRoomFavourite(
      normalizedRoomId,
      isFavourite,
    );
  }

  Future<void> respondToRoomInvite(String roomId, bool accept) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomInviteManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room invites',
      );
    }
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomInviteManager).respondToRoomInvite(
      normalizedRoomId,
      accept,
    );
  }

  Future<void> markRoomRead(String roomId, String eventId) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomReadManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support read receipts',
      );
    }
    final normalizedRoomId = roomId.trim();
    final normalizedEventId = eventId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    if (normalizedEventId.isEmpty || normalizedEventId.contains('\u0000')) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'must contain a non-empty Matrix event id without NUL bytes',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomReadManager).markRoomRead(
      normalizedRoomId,
      normalizedEventId,
    );
  }

  Future<List<MatrixSdkRoomMember>> roomMembers(String roomId) async {
    final directory = _boundary;
    if (directory is! MatrixSdkRoomMemberDirectory) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room member lookup',
      );
    }
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    await _ensureOpen();
    return (directory as MatrixSdkRoomMemberDirectory).roomMembers(
      normalizedRoomId,
    );
  }

  Future<void> inviteRoomMember(String roomId, String userId) async {
    final inviter = _boundary;
    if (inviter is! MatrixSdkRoomMemberInviter) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room member invitations',
      );
    }
    final (normalizedRoomId, normalizedUserId) = _validatedRoomUserIds(
      roomId,
      userId,
    );
    await _ensureOpen();
    await (inviter as MatrixSdkRoomMemberInviter).inviteRoomMember(
      normalizedRoomId,
      normalizedUserId,
    );
  }

  Future<bool> canModerateRoomMember({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
    required MatrixSdkRoomMemberAction action,
    int? requestedPowerLevel,
  }) async {
    final moderator = _boundary;
    if (moderator is! MatrixSdkRoomMemberModerator) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room member moderation',
      );
    }
    final (normalizedRoomId, normalizedTargetUserId) = _validatedRoomUserIds(
      roomId,
      targetUserId,
    );
    final normalizedActorUserId = _validatedUserId(actorUserId, 'actorUserId');
    await _ensureOpen();
    return (moderator as MatrixSdkRoomMemberModerator).canModerateRoomMember(
      roomId: normalizedRoomId,
      actorUserId: normalizedActorUserId,
      targetUserId: normalizedTargetUserId,
      action: action,
      requestedPowerLevel: requestedPowerLevel,
    );
  }

  Future<void> setRoomMemberPowerLevel(
    String roomId,
    String userId,
    int powerLevel,
  ) async {
    final moderator = _roomMemberModerator();
    final (normalizedRoomId, normalizedUserId) = _validatedRoomUserIds(
      roomId,
      userId,
    );
    await _ensureOpen();
    await moderator.setRoomMemberPowerLevel(
      normalizedRoomId,
      normalizedUserId,
      powerLevel,
    );
  }

  Future<void> kickRoomMember(String roomId, String userId) async {
    final moderator = _roomMemberModerator();
    final (normalizedRoomId, normalizedUserId) = _validatedRoomUserIds(
      roomId,
      userId,
    );
    await _ensureOpen();
    await moderator.kickRoomMember(normalizedRoomId, normalizedUserId);
  }

  Future<void> banRoomMember(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    final moderator = _roomMemberModerator();
    final (normalizedRoomId, normalizedUserId) = _validatedRoomUserIds(
      roomId,
      userId,
    );
    final normalizedReason = reason?.trim();
    if (normalizedReason?.contains('\u0000') == true) {
      throw ArgumentError.value(reason, 'reason', 'must not contain NUL bytes');
    }
    await _ensureOpen();
    await moderator.banRoomMember(
      normalizedRoomId,
      normalizedUserId,
      reason: normalizedReason?.isEmpty == true ? null : normalizedReason,
    );
  }

  Future<void> unbanRoomMember(String roomId, String userId) async {
    final moderator = _roomMemberModerator();
    final (normalizedRoomId, normalizedUserId) = _validatedRoomUserIds(
      roomId,
      userId,
    );
    await _ensureOpen();
    await moderator.unbanRoomMember(normalizedRoomId, normalizedUserId);
  }

  MatrixSdkRoomMemberModerator _roomMemberModerator() {
    final moderator = _boundary;
    if (moderator is! MatrixSdkRoomMemberModerator) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room member moderation',
      );
    }
    return moderator as MatrixSdkRoomMemberModerator;
  }

  (String, String) _validatedRoomUserIds(String roomId, String userId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    return (normalizedRoomId, _validatedUserId(userId, 'userId'));
  }

  String _validatedUserId(String userId, String name) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || normalizedUserId.contains('\u0000')) {
      throw ArgumentError.value(
        userId,
        name,
        'must contain a non-empty Matrix user id without NUL bytes',
      );
    }
    return normalizedUserId;
  }

  Future<void> close() async {
    await stop();
    if (!_opened) return;
    await _boundary.close();
    _opened = false;
  }

  Future<void> _ensureOpen() async {
    if (_opened) return;
    await _boundary.open(_store);
    _opened = true;
  }

  void _requireCapability(MatrixSdkCapability capability) {
    _requireBoundaryCapability(_boundary, capability);
  }

  static void _validateStoreConfiguration(
    MatrixSdkStoreConfiguration configuration,
  ) {
    if (configuration.accountId.trim().isEmpty ||
        configuration.accountId.contains('\u0000') ||
        configuration.storePath.trim().isEmpty ||
        configuration.storePath.contains('\u0000') ||
        configuration.encryptionKeyId.trim().isEmpty ||
        configuration.encryptionKeyId.contains('\u0000')) {
      throw ArgumentError.value(
        configuration,
        'store',
        'contains an invalid account id, store path, or encryption key id',
      );
    }
  }

  static void _validateSyncConfiguration(
    MatrixSdkSyncConfiguration configuration,
  ) {
    final cursor = configuration.resumeFromCursor;
    if (configuration.initialRoomListLimit <= 0 ||
        configuration.initialTimelineEventLimit <= 0 ||
        configuration.timelineEventLimit <= 0 ||
        configuration.initialTimelineEventLimit >
            configuration.timelineEventLimit ||
        cursor?.isEmpty == true ||
        cursor?.contains('\u0000') == true) {
      throw ArgumentError.value(
        configuration,
        'syncConfiguration',
        'contains invalid Matrix sync limits or resume cursor',
      );
    }
  }

  static void _requireBoundaryCapability(
    MatrixSdkBoundary boundary,
    MatrixSdkCapability capability,
  ) {
    if (boundary.capabilities.contains(capability)) return;
    throw MatrixSdkContractException(
      'Matrix SDK boundary is missing required capability ${capability.name}',
    );
  }
}
