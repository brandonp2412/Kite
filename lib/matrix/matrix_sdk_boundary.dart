import 'dart:async';
import 'dart:typed_data';

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
    this.initialRoomListLimit = 24,
    this.initialTimelineEventLimit = 8,
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

enum MatrixSdkEncryptionRecoveryState { unknown, enabled, disabled, incomplete }

enum MatrixSdkEncryptionBackupState {
  unknown,
  creating,
  enabling,
  resuming,
  enabled,
  downloading,
  disabling,
}

final class MatrixSdkEncryptionRecoveryStatus {
  const MatrixSdkEncryptionRecoveryStatus({
    required this.recoveryState,
    required this.backupState,
    required this.backupExistsOnServer,
  });

  final MatrixSdkEncryptionRecoveryState recoveryState;
  final MatrixSdkEncryptionBackupState backupState;
  final bool backupExistsOnServer;
}

final class MatrixSdkRoomKeyImportResult {
  const MatrixSdkRoomKeyImportResult({
    required this.importedCount,
    required this.totalCount,
  });

  final int importedCount;
  final int totalCount;
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

final class MatrixSdkProfileDetails {
  const MatrixSdkProfileDetails({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String? displayName;
  final String? avatarUrl;
}

final class MatrixSdkUserSearchResult {
  const MatrixSdkUserSearchResult({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String? displayName;
  final String? avatarUrl;
}

final class MatrixSdkRoomDirectoryResult {
  const MatrixSdkRoomDirectoryResult({
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
  final String? avatarUrl;
  final String joinRule;
  final bool worldReadable;
  final int joinedMembers;
}

final class MatrixSdkRoomDetails {
  MatrixSdkRoomDetails({
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
  }) : directUserIds = List<String>.unmodifiable(directUserIds);

  final String roomId;
  final String? name;
  final String? topic;
  final String? avatarUrl;
  final String? canonicalAlias;
  final String joinRule;
  final bool encryptionEnabled;
  final String historyVisibility;
  final String notificationMode;
  final bool isDirect;
  final List<String> directUserIds;
}

abstract interface class MatrixSdkMediaManager {
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  });

  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  });
}

abstract interface class MatrixSdkMediaPrefetcher {
  Future<Map<String, Uint8List>> prefetchMedia({
    required List<String> contentUris,
    Map<String, Map<String, Object?>> encryptedFiles =
        const <String, Map<String, Object?>>{},
    required int width,
    required int height,
  });
}

abstract interface class MatrixSdkProfileManager {
  Future<MatrixSdkProfileDetails> loadOwnProfile();
  Future<MatrixSdkProfileDetails> loadProfile(String userId);
  Future<List<MatrixSdkUserSearchResult>> searchUsers(String query);
  Future<Set<String>> loadIgnoredUserIds();
  Future<void> setUserIgnored(String userId, bool ignored);
  Future<void> updateDisplayName(String displayName);
  Future<void> updateAvatar(String? avatarUrl);
  Future<String> openDirectMessage(String userId);
}

final class MatrixSdkSessionDeviceDetails {
  const MatrixSdkSessionDeviceDetails({
    required this.deviceId,
    required this.isCurrent,
    required this.isVerified,
    this.displayName,
    this.lastSeenAt,
  });

  final String deviceId;
  final bool isCurrent;
  final bool? isVerified;
  final String? displayName;
  final DateTime? lastSeenAt;
}

abstract interface class MatrixSdkDeviceManager {
  Future<List<MatrixSdkSessionDeviceDetails>> loadDevices();

  Future<void> signOutDevice(String deviceId, {required String password});
}

abstract interface class MatrixSdkRoomCreator {
  Future<MatrixSdkCreatedRoom> createRoom(MatrixSdkRoomCreationRequest request);
}

abstract interface class MatrixSdkRoomDirectoryManager {
  Future<List<MatrixSdkRoomDirectoryResult>> searchRoomDirectory(String query);
  Future<void> joinRoomFromDirectory(String roomId);
  Future<void> requestRoomJoin(String roomId);
}

abstract interface class MatrixSdkRoomSettingsManager {
  Future<MatrixSdkRoomDetails> roomDetails(String roomId);
  Future<void> setRoomName(String roomId, String? name);
  Future<void> setRoomTopic(String roomId, String? topic);
  Future<void> setRoomAvatar(String roomId, String? avatarUrl);
  Future<void> setRoomCanonicalAlias(String roomId, String? canonicalAlias);
  Future<void> setRoomJoinRule(String roomId, String joinRule);
  Future<void> enableRoomEncryption(String roomId);
  Future<void> setRoomHistoryVisibility(String roomId, String visibility);
  Future<void> setRoomNotificationMode(String roomId, String mode);
}

abstract interface class MatrixSdkRoomLifecycleManager {
  Future<void> reportRoom(String roomId, {String? reason});

  Future<void> reportUser(String roomId, String userId, {String? reason});

  Future<void> leaveRoom(String roomId);

  Future<void> forgetRoom(String roomId);
}

abstract interface class MatrixSdkTimelineModerationManager {
  Future<void> reportEvent(String roomId, String eventId, {String? reason});
}

abstract interface class MatrixSdkTimelineRedactionManager {
  Future<void> redactEvent(
    String roomId,
    String eventId, {
    required String transactionId,
  });
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

enum MatrixSdkCrossSigningTrustState { unknown, unverified, verified }

final class MatrixSdkRoomEncryptionTrustDetails {
  const MatrixSdkRoomEncryptionTrustDetails({
    required this.roomId,
    required this.isEncrypted,
    required this.allDevicesVerified,
  });

  final String roomId;
  final bool isEncrypted;
  final bool? allDevicesVerified;
}

abstract interface class MatrixSdkRoomEncryptionTrustManager {
  Future<MatrixSdkCrossSigningTrustState> loadCrossSigningTrust();

  Future<MatrixSdkRoomEncryptionTrustDetails> loadRoomEncryptionTrust(
    String roomId,
  );
}

abstract interface class MatrixSdkEncryptionRecoveryManager {
  Future<MatrixSdkEncryptionRecoveryStatus> encryptionRecoveryStatus();

  Future<MatrixSdkEncryptionRecoveryStatus> createEncryptedBackup();

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryption(String secret);

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryptedHistory();

  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  });
}

abstract interface class MatrixSdkTextMessageSender {
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
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

  static const int _mediaCacheEntryLimit = 48;
  static const int _mediaCacheByteLimit = 64 * 1024 * 1024;
  final Map<(String, int, int), Future<Uint8List>> _mediaLoads = {};
  final Map<(int, int), Map<String, Completer<Uint8List>>> _avatarBatches = {};

  final Map<(String, int, int), Uint8List> _mediaCache =
      <(String, int, int), Uint8List>{};
  int _mediaCacheBytes = 0;
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

  Future<MatrixSdkCrossSigningTrustState> loadCrossSigningTrust() async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomEncryptionTrustManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support cross-signing trust',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkRoomEncryptionTrustManager)
        .loadCrossSigningTrust();
  }

  Future<MatrixSdkRoomEncryptionTrustDetails> loadRoomEncryptionTrust(
    String roomId,
  ) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomEncryptionTrustManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room encryption trust',
      );
    }
    final normalizedRoomId = _validatedRoomId(roomId);
    await _ensureOpen();
    final trust = await (manager as MatrixSdkRoomEncryptionTrustManager)
        .loadRoomEncryptionTrust(normalizedRoomId);
    if (trust.roomId != normalizedRoomId ||
        (!trust.isEncrypted && trust.allDevicesVerified != null)) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary returned invalid room encryption trust data',
      );
    }
    return trust;
  }

  Future<MatrixSdkEncryptionRecoveryStatus> encryptionRecoveryStatus() async {
    final manager = _boundary;
    if (manager is! MatrixSdkEncryptionRecoveryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support encryption recovery',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkEncryptionRecoveryManager)
        .encryptionRecoveryStatus();
  }

  Future<MatrixSdkEncryptionRecoveryStatus> createEncryptedBackup() async {
    final manager = _boundary;
    if (manager is! MatrixSdkEncryptionRecoveryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support encryption recovery',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkEncryptionRecoveryManager)
        .createEncryptedBackup();
  }

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryption(
    String secret,
  ) async {
    final manager = _boundary;
    if (manager is! MatrixSdkEncryptionRecoveryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support encryption recovery',
      );
    }
    if (secret.isEmpty || secret.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'secret',
        'must not be empty or contain NUL bytes',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkEncryptionRecoveryManager).recoverEncryption(
      secret,
    );
  }

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryptedHistory() async {
    final manager = _boundary;
    if (manager is! MatrixSdkEncryptionRecoveryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support encryption recovery',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkEncryptionRecoveryManager)
        .recoverEncryptedHistory();
  }

  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkEncryptionRecoveryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support encryption recovery',
      );
    }
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        'path',
        'must not be empty or contain NUL bytes',
      );
    }
    if (passphrase.isEmpty || passphrase.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'passphrase',
        'must not be empty or contain NUL bytes',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkEncryptionRecoveryManager).importRoomKeyBackup(
      path: path,
      passphrase: passphrase,
    );
  }

  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) async {
    final sender = _boundary;
    if (sender is! MatrixSdkTextMessageSender) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support text messages',
      );
    }
    await _ensureOpen();
    final normalizedReplyToEventId = replyToEventId?.trim();
    if (normalizedReplyToEventId != null &&
        (normalizedReplyToEventId.isEmpty ||
            normalizedReplyToEventId.contains('\u0000'))) {
      throw ArgumentError.value(
        replyToEventId,
        'replyToEventId',
        'must not be empty or contain NUL bytes',
      );
    }
    final normalizedReplacementEventId = replacementEventId?.trim();
    if (normalizedReplacementEventId != null &&
        (normalizedReplacementEventId.isEmpty ||
            normalizedReplacementEventId.contains('\u0000'))) {
      throw ArgumentError.value(
        replacementEventId,
        'replacementEventId',
        'must not be empty or contain NUL bytes',
      );
    }
    if (normalizedReplyToEventId != null &&
        normalizedReplacementEventId != null) {
      throw ArgumentError(
        'A Matrix text event cannot be both a reply and a replacement.',
      );
    }
    return (sender as MatrixSdkTextMessageSender).sendTextMessage(
      roomId: roomId,
      transactionId: transactionId,
      body: body,
      replyToEventId: normalizedReplyToEventId,
      replacementEventId: normalizedReplacementEventId,
    );
  }

  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkMediaManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support media uploads',
      );
    }
    final normalizedMimeType = mimeType.trim();
    if (normalizedMimeType.isEmpty || normalizedMimeType.contains('\u0000')) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'must not be empty or contain NUL bytes',
      );
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    await _ensureOpen();
    return (manager as MatrixSdkMediaManager).uploadMedia(
      mimeType: normalizedMimeType,
      bytes: bytes,
    );
  }

  Future<int> prefetchMedia({
    required List<String> contentUris,
    Map<String, Map<String, Object?>> encryptedFiles =
        const <String, Map<String, Object?>>{},
    required int width,
    required int height,
  }) async {
    final prefetcher = _boundary;
    if (prefetcher is! MatrixSdkMediaPrefetcher || contentUris.isEmpty) {
      return 0;
    }
    final normalizedUris = <String>[];
    final seen = <String>{};
    for (final contentUri in contentUris) {
      final normalized = contentUri.trim();
      final uri = Uri.tryParse(normalized);
      if (uri == null ||
          uri.scheme != 'mxc' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.pathSegments.length != 1 ||
          uri.pathSegments.single.isEmpty ||
          normalized.contains('\u0000')) {
        throw ArgumentError.value(
          contentUri,
          'contentUris',
          'must contain only valid Matrix content URIs without NUL bytes',
        );
      }
      if (seen.add(normalized)) normalizedUris.add(normalized);
    }
    for (final entry in encryptedFiles.entries) {
      if (!seen.contains(entry.key) || entry.value['url'] != entry.key) {
        throw ArgumentError.value(
          encryptedFiles,
          'encryptedFiles',
          'must map requested Matrix content URIs to matching encrypted files',
        );
      }
    }
    if (normalizedUris.length > 32) {
      throw ArgumentError.value(
        contentUris,
        'contentUris',
        'must contain at most 32 unique Matrix content URIs',
      );
    }
    if (width <= 0 || width > 4096) {
      throw ArgumentError.value(width, 'width', 'must be between 1 and 4096');
    }
    if (height <= 0 || height > 4096) {
      throw ArgumentError.value(height, 'height', 'must be between 1 and 4096');
    }
    var completed = 0;
    final pendingUris = <String>[];
    for (final contentUri in normalizedUris) {
      if (_cachedMedia(contentUri, width, height) != null) {
        completed += 1;
      } else {
        pendingUris.add(contentUri);
      }
    }
    if (pendingUris.isEmpty) return completed;

    await _ensureOpen();
    final prefetched = await (prefetcher as MatrixSdkMediaPrefetcher)
        .prefetchMedia(
          contentUris: pendingUris,
          encryptedFiles: <String, Map<String, Object?>>{
            for (final contentUri in pendingUris)
              contentUri: ?encryptedFiles[contentUri],
          },
          width: width,
          height: height,
        );
    for (final entry in prefetched.entries) {
      if (!seen.contains(entry.key) || entry.value.isEmpty) {
        throw const MatrixSdkContractException(
          'Matrix SDK boundary returned invalid prefetched media',
        );
      }
      _rememberMedia(
        contentUri: entry.key,
        width: width,
        height: height,
        bytes: entry.value,
      );
    }
    return completed + prefetched.length;
  }

  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkMediaManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support media downloads',
      );
    }
    final normalizedContentUri = contentUri.trim();
    final uri = Uri.tryParse(normalizedContentUri);
    if (uri == null ||
        uri.scheme != 'mxc' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        uri.pathSegments.single.isEmpty ||
        normalizedContentUri.contains('\u0000')) {
      throw ArgumentError.value(
        contentUri,
        'contentUri',
        'must be a valid Matrix content URI without NUL bytes',
      );
    }
    if (encryptedFile != null) {
      final encryptedUrl = encryptedFile['url'];
      if (encryptedUrl != normalizedContentUri) {
        throw ArgumentError.value(
          encryptedFile,
          'encryptedFile',
          'must describe the requested Matrix content URI',
        );
      }
    }
    if (width <= 0 || width > 4096) {
      throw ArgumentError.value(width, 'width', 'must be between 1 and 4096');
    }
    if (height <= 0 || height > 4096) {
      throw ArgumentError.value(height, 'height', 'must be between 1 and 4096');
    }
    final cached = _cachedMedia(normalizedContentUri, width, height);
    if (cached != null) return cached;
    await _ensureOpen();
    final key = (normalizedContentUri, width, height);
    if (encryptedFile == null) {
      final pending = _mediaLoads[key];
      if (pending != null) return pending;
    }
    final download =
        encryptedFile == null &&
            width <= 256 &&
            height <= 256 &&
            _boundary is MatrixSdkMediaPrefetcher
        ? _batchAvatar(normalizedContentUri, width, height)
        : (manager as MatrixSdkMediaManager).downloadMedia(
            contentUri: normalizedContentUri,
            encryptedFile: encryptedFile,
            width: width,
            height: height,
          );
    final load = download.then((bytes) {
      if (bytes.isEmpty) {
        throw const MatrixSdkContractException(
          'Matrix SDK boundary returned empty media data',
        );
      }
      _rememberMedia(
        contentUri: normalizedContentUri,
        width: width,
        height: height,
        bytes: bytes,
      );
      return bytes;
    });
    if (encryptedFile == null) _mediaLoads[key] = load;
    try {
      return await load;
    } finally {
      if (identical(_mediaLoads[key], load)) _mediaLoads.remove(key);
    }
  }

  Future<Uint8List> _batchAvatar(String uri, int width, int height) {
    final size = (width, height);
    final batch = _avatarBatches.putIfAbsent(size, () {
      final pending = <String, Completer<Uint8List>>{};
      Timer.run(() => unawaited(_flushAvatarBatch(size, pending)));
      return pending;
    });
    return (batch[uri] ??= Completer<Uint8List>()).future;
  }

  Future<void> _flushAvatarBatch(
    (int, int) size,
    Map<String, Completer<Uint8List>> batch,
  ) async {
    _avatarBatches.remove(size);
    final entries = batch.entries.toList();
    for (var offset = 0; offset < entries.length; offset += 6) {
      final group = entries.skip(offset).take(6).toList();
      Map<String, Uint8List> result = {};
      try {
        result = await (_boundary as MatrixSdkMediaPrefetcher).prefetchMedia(
          contentUris: group.map((entry) => entry.key).toList(),
          width: size.$1,
          height: size.$2,
        );
      } catch (_) {
        // Let individual downloads provide their normal fallback/error handling.
      }
      for (final entry in group) {
        final bytes = result[entry.key];
        if (bytes != null && bytes.isNotEmpty) {
          entry.value.complete(bytes);
        } else {
          entry.value.complete(
            Future<Uint8List>.sync(
              () => (_boundary as MatrixSdkMediaManager).downloadMedia(
                contentUri: entry.key,
                width: size.$1,
                height: size.$2,
              ),
            ),
          );
        }
      }
    }
  }

  Future<MatrixSdkProfileDetails> loadOwnProfile() async {
    final manager = _profileManager();
    await _ensureOpen();
    return manager.loadOwnProfile();
  }

  Future<MatrixSdkProfileDetails> loadProfile(String userId) async {
    final manager = _profileManager();
    final normalizedUserId = _validatedUserId(userId, 'userId');
    await _ensureOpen();
    return manager.loadProfile(normalizedUserId);
  }

  Future<List<MatrixSdkUserSearchResult>> searchUsers(String query) async {
    final manager = _profileManager();
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2 || normalizedQuery.contains('\u0000')) {
      throw ArgumentError.value(
        query,
        'query',
        'must contain at least two non-NUL characters',
      );
    }
    await _ensureOpen();
    return manager.searchUsers(normalizedQuery);
  }

  Future<List<MatrixSdkRoomDirectoryResult>> searchRoomDirectory(
    String query,
  ) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomDirectoryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room directory search',
      );
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.contains('\u0000')) {
      throw ArgumentError.value(
        query,
        'query',
        'must not contain NUL characters',
      );
    }
    await _ensureOpen();
    return (manager as MatrixSdkRoomDirectoryManager).searchRoomDirectory(
      normalizedQuery,
    );
  }

  Future<void> joinRoomFromDirectory(String roomId) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomDirectoryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room directory membership',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomDirectoryManager).joinRoomFromDirectory(
      _validatedRoomId(roomId),
    );
  }

  Future<void> requestRoomJoin(String roomId) async {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomDirectoryManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room directory membership',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkRoomDirectoryManager).requestRoomJoin(
      _validatedRoomId(roomId),
    );
  }

  Future<Set<String>> loadIgnoredUserIds() async {
    final manager = _profileManager();
    await _ensureOpen();
    final userIds = await manager.loadIgnoredUserIds();
    return Set<String>.unmodifiable(
      userIds.map((userId) => _validatedUserId(userId, 'ignoredUserId')),
    );
  }

  Future<void> setUserIgnored(String userId, bool ignored) async {
    final manager = _profileManager();
    final normalizedUserId = _validatedUserId(userId, 'userId');
    await _ensureOpen();
    await manager.setUserIgnored(normalizedUserId, ignored);
  }

  Future<List<MatrixSdkSessionDeviceDetails>> loadDevices() async {
    final manager = _boundary is MatrixSdkDeviceManager
        ? _boundary as MatrixSdkDeviceManager
        : null;
    if (manager == null) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support device listing',
      );
    }
    await _ensureOpen();
    final devices = await manager.loadDevices();
    final ids = <String>{};
    var currentCount = 0;
    for (final device in devices) {
      if (device.deviceId.trim() != device.deviceId ||
          device.deviceId.isEmpty ||
          !ids.add(device.deviceId)) {
        throw const MatrixSdkContractException(
          'Matrix SDK boundary returned invalid device data',
        );
      }
      if (device.isCurrent) currentCount += 1;
    }
    if (devices.isNotEmpty && currentCount != 1) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary returned invalid current-device data',
      );
    }
    return List<MatrixSdkSessionDeviceDetails>.unmodifiable(devices);
  }

  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {
    final manager = _boundary is MatrixSdkDeviceManager
        ? _boundary as MatrixSdkDeviceManager
        : null;
    if (manager == null) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support device management',
      );
    }
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty ||
        normalizedDeviceId != deviceId ||
        normalizedDeviceId.contains('\u0000')) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'must be a valid device ID',
      );
    }
    if (password.isEmpty || password.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'password',
        'must not be empty or contain NUL bytes',
      );
    }
    await _ensureOpen();
    await manager.signOutDevice(normalizedDeviceId, password: password);
  }

  Future<void> updateDisplayName(String displayName) async {
    final manager = _profileManager();
    await _ensureOpen();
    await manager.updateDisplayName(displayName.trim());
  }

  Future<void> updateAvatar(String? avatarUrl) async {
    final manager = _profileManager();
    final normalizedAvatar = avatarUrl?.trim();
    if (normalizedAvatar != null && normalizedAvatar.contains('\u0000')) {
      throw ArgumentError.value(
        avatarUrl,
        'avatarUrl',
        'must not contain NUL bytes',
      );
    }
    await _ensureOpen();
    await manager.updateAvatar(
      normalizedAvatar == null || normalizedAvatar.isEmpty
          ? null
          : normalizedAvatar,
    );
  }

  Future<String> openDirectMessage(String userId) async {
    final manager = _profileManager();
    final normalizedUserId = _validatedUserId(userId, 'userId');
    await _ensureOpen();
    return manager.openDirectMessage(normalizedUserId);
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

  Future<MatrixSdkRoomDetails> roomDetails(String roomId) async {
    final manager = _roomSettingsManager();
    final normalizedRoomId = _validatedRoomId(roomId);
    await _ensureOpen();
    return manager.roomDetails(normalizedRoomId);
  }

  Future<void> setRoomName(String roomId, String? name) => _updateRoomSetting(
    roomId,
    (manager, normalizedRoomId) => manager.setRoomName(normalizedRoomId, name),
  );

  Future<void> setRoomTopic(String roomId, String? topic) => _updateRoomSetting(
    roomId,
    (manager, normalizedRoomId) =>
        manager.setRoomTopic(normalizedRoomId, topic),
  );

  Future<void> setRoomAvatar(String roomId, String? avatarUrl) =>
      _updateRoomSetting(
        roomId,
        (manager, normalizedRoomId) =>
            manager.setRoomAvatar(normalizedRoomId, avatarUrl),
      );

  Future<void> setRoomCanonicalAlias(String roomId, String? canonicalAlias) =>
      _updateRoomSetting(
        roomId,
        (manager, normalizedRoomId) =>
            manager.setRoomCanonicalAlias(normalizedRoomId, canonicalAlias),
      );

  Future<void> setRoomJoinRule(String roomId, String joinRule) =>
      _updateRoomSetting(
        roomId,
        (manager, normalizedRoomId) =>
            manager.setRoomJoinRule(normalizedRoomId, joinRule),
      );

  Future<void> enableRoomEncryption(String roomId) => _updateRoomSetting(
    roomId,
    (manager, normalizedRoomId) =>
        manager.enableRoomEncryption(normalizedRoomId),
  );

  Future<void> setRoomHistoryVisibility(String roomId, String visibility) =>
      _updateRoomSetting(
        roomId,
        (manager, normalizedRoomId) =>
            manager.setRoomHistoryVisibility(normalizedRoomId, visibility),
      );

  Future<void> setRoomNotificationMode(String roomId, String mode) =>
      _updateRoomSetting(
        roomId,
        (manager, normalizedRoomId) =>
            manager.setRoomNotificationMode(normalizedRoomId, mode),
      );

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

  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkTimelineModerationManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support event reporting',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkTimelineModerationManager).reportEvent(
      roomId,
      eventId,
      reason: reason,
    );
  }

  Future<void> redactEvent(
    String roomId,
    String eventId, {
    required String transactionId,
  }) async {
    final manager = _boundary;
    if (manager is! MatrixSdkTimelineRedactionManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support event redaction',
      );
    }
    final normalizedTransactionId = transactionId.trim();
    if (normalizedTransactionId.isEmpty ||
        normalizedTransactionId.contains('\u0000')) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'must not be empty or contain NUL bytes',
      );
    }
    await _ensureOpen();
    await (manager as MatrixSdkTimelineRedactionManager).redactEvent(
      roomId,
      eventId,
      transactionId: normalizedTransactionId,
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

  MatrixSdkProfileManager _profileManager() {
    final manager = _boundary;
    if (manager is! MatrixSdkProfileManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support profile management',
      );
    }
    return manager as MatrixSdkProfileManager;
  }

  MatrixSdkRoomSettingsManager _roomSettingsManager() {
    final manager = _boundary;
    if (manager is! MatrixSdkRoomSettingsManager) {
      throw const MatrixSdkContractException(
        'Matrix SDK boundary does not support room settings',
      );
    }
    return manager as MatrixSdkRoomSettingsManager;
  }

  String _validatedRoomId(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must contain a non-empty Matrix room id without NUL bytes',
      );
    }
    return normalizedRoomId;
  }

  Future<void> _updateRoomSetting(
    String roomId,
    Future<void> Function(MatrixSdkRoomSettingsManager manager, String roomId)
    update,
  ) async {
    final manager = _roomSettingsManager();
    final normalizedRoomId = _validatedRoomId(roomId);
    await _ensureOpen();
    await update(manager, normalizedRoomId);
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
    _mediaCache.clear();
    _mediaCacheBytes = 0;
    _mediaLoads.clear();
    _avatarBatches.clear();
    if (!_opened) return;
    await _boundary.close();
    _opened = false;
  }

  Uint8List? _cachedMedia(String contentUri, int width, int height) {
    final key = (contentUri, width, height);
    final bytes = _mediaCache.remove(key);
    if (bytes == null) return null;
    _mediaCache[key] = bytes;
    return bytes;
  }

  void _rememberMedia({
    required String contentUri,
    required int width,
    required int height,
    required Uint8List bytes,
  }) {
    if (bytes.lengthInBytes > _mediaCacheByteLimit) return;

    final key = (contentUri, width, height);
    final previous = _mediaCache.remove(key);
    if (previous != null) {
      _mediaCacheBytes -= previous.lengthInBytes;
    }
    _mediaCache[key] = bytes;
    _mediaCacheBytes += bytes.lengthInBytes;

    while (_mediaCache.length > _mediaCacheEntryLimit ||
        _mediaCacheBytes > _mediaCacheByteLimit) {
      final oldestKey = _mediaCache.keys.first;
      final removed = _mediaCache.remove(oldestKey);
      if (removed != null) {
        _mediaCacheBytes -= removed.lengthInBytes;
      }
    }
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
