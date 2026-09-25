import 'dart:io';
import 'dart:typed_data';

import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:kite/matrix/presentation_store.dart';
import 'package:signals/signals.dart';

typedef MatrixProductionBoundaryBuilder = MatrixSdkBoundary Function(
  String accountId,
  Uri homeserver,
);

String matrixRustNativeLibraryPath() {
  if (Platform.isAndroid || Platform.isLinux) {
    return 'libkite_matrix_bridge.so';
  }
  if (Platform.isWindows) {
    return 'kite_matrix_bridge.dll';
  }
  if (Platform.isMacOS) {
    return 'libkite_matrix_bridge.dylib';
  }
  throw UnsupportedError(
    'The production Matrix Rust bridge is not configured for this platform',
  );
}

final class MatrixProductionRuntime
    implements MatrixActivityRuntime, MatrixConnectivityRuntime {
  factory MatrixProductionRuntime({
    required Directory rootDirectory,
    required MatrixSdkStoreSecretResolver resolveStoreSecret,
    required String Function(String accountId) encryptionKeyIdForAccount,
    MatrixAppActivity initialActivity = MatrixAppActivity.foreground,
    MatrixNetworkState initialNetworkState = MatrixNetworkState.online,
    bool syncWhileBackgrounded = false,
    MatrixSyncBatchObserver? onSyncBatch,
    MatrixProductionBoundaryBuilder? boundaryBuilder,
    MatrixRustBridge? nativeBridge,
    StructuredLogger? logger,
    CrashReporter? crashReporter,
  }) {
    return MatrixProductionRuntime._(
      rootDirectory: rootDirectory,
      resolveStoreSecret: resolveStoreSecret,
      encryptionKeyIdForAccount: encryptionKeyIdForAccount,
      initialActivity: initialActivity,
      initialNetworkState: initialNetworkState,
      syncWhileBackgrounded: syncWhileBackgrounded,
      onSyncBatch: onSyncBatch,
      boundaryBuilder: boundaryBuilder,
      nativeBridge: nativeBridge,
      logger: logger,
      crashReporter: crashReporter,
    );
  }

  MatrixProductionRuntime._({
    required Directory rootDirectory,
    required this._resolveStoreSecret,
    required String Function(String accountId) encryptionKeyIdForAccount,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
    required bool syncWhileBackgrounded,
    required MatrixSyncBatchObserver? onSyncBatch,
    required this._boundaryBuilder,
    required this._nativeBridge,
    required this._logger,
    required this._crashReporter,
  }) {
    final rootPath = rootDirectory.path.trim();
    if (rootPath.isEmpty || rootPath.contains('\u0000')) {
      throw ArgumentError.value(
        rootDirectory.path,
        'rootDirectory',
        'must have a non-empty path without NUL bytes',
      );
    }
    accounts = MatrixAccountRuntimeRegistry(
      storeRegistry: MatrixAccountStoreRegistry(
        rootPath: '${rootDirectory.path}/matrix-sdk',
        encryptionKeyIdForAccount: encryptionKeyIdForAccount,
      ),
      boundaryFactory: _buildBoundary,
      presentationStore: FileMatrixPresentationStore(
        Directory('${rootDirectory.path}/presentation'),
      ),
      initialActivity: initialActivity,
      initialNetworkState: initialNetworkState,
      syncWhileBackgrounded: syncWhileBackgrounded,
      onSyncBatch: onSyncBatch,
    );
  }

  final MatrixProductionBoundaryBuilder? _boundaryBuilder;
  final MatrixRustBridge? _nativeBridge;
  final MatrixSdkStoreSecretResolver _resolveStoreSecret;
  final StructuredLogger? _logger;
  final CrashReporter? _crashReporter;
  final Map<String, Uri> _homeservers = <String, Uri>{};

  late final MatrixAccountRuntimeRegistry accounts;

  ReadonlySignal<String?> get activeAccountId => accounts.activeAccountId;

  MatrixPresentationCache? get activeCache => accounts.activeCache;

  ReadonlySignal<MatrixSyncState>? get activeSyncState =>
      accounts.activeSyncState;

  Future<MatrixSdkEncryptionRecoveryStatus> encryptionRecoveryStatus({
    required String accountId,
  }) => accounts.encryptionRecoveryStatus(accountId: accountId);

  Future<MatrixSdkEncryptionRecoveryStatus> createEncryptedBackup({
    required String accountId,
  }) => accounts.createEncryptedBackup(accountId: accountId);

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryption({
    required String accountId,
    required String secret,
  }) => accounts.recoverEncryption(accountId: accountId, secret: secret);

  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryptedHistory({
    required String accountId,
  }) => accounts.recoverEncryptedHistory(accountId: accountId);

  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String accountId,
    required String path,
    required String passphrase,
  }) => accounts.importRoomKeyBackup(
    accountId: accountId,
    path: path,
    passphrase: passphrase,
  );

  void registerAuthenticatedAccount({
    required String accountId,
    required Uri homeserver,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    final normalizedHomeserver = _normalizeHomeserver(homeserver);
    final existing = _homeservers[normalizedAccountId];
    if (existing == normalizedHomeserver) return;
    if (existing != null ||
        accounts.loadedAccountIds.contains(normalizedAccountId)) {
      throw StateError(
        'Cannot change the homeserver of a loaded Matrix account runtime',
      );
    }
    _homeservers[normalizedAccountId] = normalizedHomeserver;
  }

  bool isAccountRegistered(String accountId) {
    final normalizedAccountId = accountId.trim();
    return normalizedAccountId.isNotEmpty &&
        _homeservers.containsKey(normalizedAccountId);
  }

  Future<MatrixPresentationCache> activate(String accountId) {
    final normalizedAccountId = _requireRegistered(accountId);
    return accounts.activate(normalizedAccountId);
  }

  Future<MatrixPresentationCache> activateCached(String accountId) {
    final normalizedAccountId = _requireRegistered(accountId);
    return accounts.activateCached(normalizedAccountId);
  }

  Future<void> resumeActive() => accounts.resumeActive();

  Future<void> restartAccount(String accountId) =>
      accounts.restartAccount(accountId);

  Future<void> refreshAfterEncryptionRecovery({required String accountId}) =>
      accounts.refreshAfterEncryptionRecovery(accountId: accountId);

  @override
  Future<void> updateActivity(MatrixAppActivity activity) =>
      accounts.updateActivity(activity);

  @override
  Future<void> updateNetworkState(MatrixNetworkState state) =>
      accounts.updateNetworkState(state);

  ReadonlySignal<MatrixPaginationState>? paginationState({
    required String accountId,
    required String roomId,
  }) {
    return accounts.activePaginationState(accountId: accountId, roomId: roomId);
  }

  Future<void> onTimelineViewportChanged({
    required String accountId,
    required String roomId,
    required int oldestVisibleIndex,
    required bool hasMoreHistory,
  }) {
    return accounts.onTimelineViewportChanged(
      accountId: accountId,
      roomId: roomId,
      oldestVisibleIndex: oldestVisibleIndex,
      hasMoreHistory: hasMoreHistory,
    );
  }

  Future<String> uploadMedia({
    required String accountId,
    required String mimeType,
    required Uint8List bytes,
  }) => accounts.uploadMedia(
    accountId: accountId,
    mimeType: mimeType,
    bytes: bytes,
  );

  Future<int> prefetchMedia({
    required String accountId,
    required List<String> contentUris,
    Map<String, Map<String, Object?>> encryptedFiles =
        const <String, Map<String, Object?>>{},
    required int width,
    required int height,
  }) => accounts.prefetchMedia(
    accountId: accountId,
    contentUris: contentUris,
    encryptedFiles: encryptedFiles,
    width: width,
    height: height,
  );

  Future<Uint8List> downloadMedia({
    required String accountId,
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) => accounts.downloadMedia(
    accountId: accountId,
    contentUri: contentUri,
    encryptedFile: encryptedFile,
    width: width,
    height: height,
  );

  Future<MatrixSdkProfileDetails> loadOwnProfile({required String accountId}) =>
      accounts.loadOwnProfile(accountId: accountId);

  Future<MatrixSdkProfileDetails> loadProfile({
    required String accountId,
    required String userId,
  }) => accounts.loadProfile(accountId: accountId, userId: userId);

  Future<List<MatrixSdkUserSearchResult>> searchUsers({
    required String accountId,
    required String query,
  }) => accounts.searchUsers(accountId: accountId, query: query);

  Future<List<MatrixSdkRoomDirectoryResult>> searchRoomDirectory({
    required String accountId,
    required String query,
  }) => accounts.searchRoomDirectory(accountId: accountId, query: query);

  Future<void> joinRoomFromDirectory({
    required String accountId,
    required String roomId,
  }) => accounts.joinRoomFromDirectory(accountId: accountId, roomId: roomId);

  Future<void> requestRoomJoin({
    required String accountId,
    required String roomId,
  }) => accounts.requestRoomJoin(accountId: accountId, roomId: roomId);

  Future<Set<String>> loadIgnoredUserIds({required String accountId}) =>
      accounts.loadIgnoredUserIds(accountId: accountId);

  Future<void> setUserIgnored({
    required String accountId,
    required String userId,
    required bool ignored,
  }) => accounts.setUserIgnored(
    accountId: accountId,
    userId: userId,
    ignored: ignored,
  );

  Future<MatrixSdkCrossSigningTrustState> loadCrossSigningTrust({
    required String accountId,
  }) => accounts.loadCrossSigningTrust(accountId: accountId);

  Future<MatrixSdkRoomEncryptionTrustDetails> loadRoomEncryptionTrust({
    required String accountId,
    required String roomId,
  }) => accounts.loadRoomEncryptionTrust(accountId: accountId, roomId: roomId);

  Future<List<MatrixSdkSessionDeviceDetails>> loadDevices({
    required String accountId,
  }) => accounts.loadDevices(accountId: accountId);

  Future<void> signOutDevice({
    required String accountId,
    required String deviceId,
    required String password,
  }) => accounts.signOutDevice(
    accountId: accountId,
    deviceId: deviceId,
    password: password,
  );

  Future<void> updateDisplayName({
    required String accountId,
    required String displayName,
  }) => accounts.updateDisplayName(
    accountId: accountId,
    displayName: displayName,
  );

  Future<void> updateAvatar({
    required String accountId,
    required String? avatarUrl,
  }) => accounts.updateAvatar(accountId: accountId, avatarUrl: avatarUrl);

  Future<String> openDirectMessage({
    required String accountId,
    required String userId,
  }) => accounts.openDirectMessage(accountId: accountId, userId: userId);

  Future<MatrixSdkCreatedRoom> createRoom({
    required String accountId,
    required MatrixSdkRoomCreationRequest request,
  }) {
    return accounts.createRoom(accountId: accountId, request: request);
  }

  Future<List<MatrixSdkSpaceHierarchyEntry>> loadSpaceHierarchy({
    required String accountId,
    required String spaceId,
  }) => accounts.loadSpaceHierarchy(accountId: accountId, spaceId: spaceId);

  Future<void> setSpaceChild({
    required String accountId,
    required String spaceId,
    required String roomId,
    required bool linked,
  }) => accounts.setSpaceChild(
    accountId: accountId,
    spaceId: spaceId,
    roomId: roomId,
    linked: linked,
  );

  Future<MatrixSdkRoomDetails> roomDetails({
    required String accountId,
    required String roomId,
  }) => accounts.roomDetails(accountId: accountId, roomId: roomId);

  Future<void> setRoomName({
    required String accountId,
    required String roomId,
    required String? name,
  }) => accounts.setRoomName(accountId: accountId, roomId: roomId, name: name);

  Future<void> setRoomTopic({
    required String accountId,
    required String roomId,
    required String? topic,
  }) =>
      accounts.setRoomTopic(accountId: accountId, roomId: roomId, topic: topic);

  Future<void> setRoomAvatar({
    required String accountId,
    required String roomId,
    required String? avatarUrl,
  }) => accounts.setRoomAvatar(
    accountId: accountId,
    roomId: roomId,
    avatarUrl: avatarUrl,
  );

  Future<void> setRoomCanonicalAlias({
    required String accountId,
    required String roomId,
    required String? canonicalAlias,
  }) => accounts.setRoomCanonicalAlias(
    accountId: accountId,
    roomId: roomId,
    canonicalAlias: canonicalAlias,
  );

  Future<void> setRoomJoinRule({
    required String accountId,
    required String roomId,
    required String joinRule,
  }) => accounts.setRoomJoinRule(
    accountId: accountId,
    roomId: roomId,
    joinRule: joinRule,
  );

  Future<void> enableRoomEncryption({
    required String accountId,
    required String roomId,
  }) => accounts.enableRoomEncryption(accountId: accountId, roomId: roomId);

  Future<void> setRoomHistoryVisibility({
    required String accountId,
    required String roomId,
    required String visibility,
  }) => accounts.setRoomHistoryVisibility(
    accountId: accountId,
    roomId: roomId,
    visibility: visibility,
  );

  Future<void> setRoomNotificationMode({
    required String accountId,
    required String roomId,
    required String mode,
  }) => accounts.setRoomNotificationMode(
    accountId: accountId,
    roomId: roomId,
    mode: mode,
  );

  Future<void> reportRoom({
    required String accountId,
    required String roomId,
    String? reason,
  }) {
    return accounts.reportRoom(
      accountId: accountId,
      roomId: roomId,
      reason: reason,
    );
  }

  Future<void> reportUser({
    required String accountId,
    required String roomId,
    required String userId,
    String? reason,
  }) {
    return accounts.reportUser(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
      reason: reason,
    );
  }

  Future<void> reportEvent({
    required String accountId,
    required String roomId,
    required String eventId,
    String? reason,
  }) {
    return accounts.reportEvent(
      accountId: accountId,
      roomId: roomId,
      eventId: eventId,
      reason: reason,
    );
  }

  Future<void> redactEvent({
    required String accountId,
    required String roomId,
    required String eventId,
    required String transactionId,
  }) {
    return accounts.redactEvent(
      accountId: accountId,
      roomId: roomId,
      eventId: eventId,
      transactionId: transactionId,
    );
  }

  Future<void> leaveRoom({required String accountId, required String roomId}) {
    return accounts.leaveRoom(accountId: accountId, roomId: roomId);
  }

  Future<void> forgetRoom({required String accountId, required String roomId}) {
    return accounts.forgetRoom(accountId: accountId, roomId: roomId);
  }

  Future<void> setRoomFavourite({
    required String accountId,
    required String roomId,
    required bool isFavourite,
  }) {
    return accounts.setRoomFavourite(
      accountId: accountId,
      roomId: roomId,
      isFavourite: isFavourite,
    );
  }

  Future<void> respondToRoomInvite({
    required String accountId,
    required String roomId,
    required bool accept,
  }) {
    return accounts.respondToRoomInvite(
      accountId: accountId,
      roomId: roomId,
      accept: accept,
    );
  }

  Future<void> markRoomRead({
    required String accountId,
    required String roomId,
  }) {
    return accounts.markRoomRead(accountId: accountId, roomId: roomId);
  }

  Future<void> markAllRoomsRead({required String accountId}) {
    return accounts.markAllRoomsRead(accountId: accountId);
  }

  Future<List<MatrixSdkRoomMember>> roomMembers({
    required String accountId,
    required String roomId,
  }) {
    return accounts.roomMembers(accountId: accountId, roomId: roomId);
  }

  Future<void> inviteRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) {
    return accounts.inviteRoomMember(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
    );
  }

  Future<bool> canModerateRoomMember({
    required String accountId,
    required String roomId,
    required String actorUserId,
    required String targetUserId,
    required MatrixSdkRoomMemberAction action,
    int? requestedPowerLevel,
  }) {
    return accounts.canModerateRoomMember(
      accountId: accountId,
      roomId: roomId,
      actorUserId: actorUserId,
      targetUserId: targetUserId,
      action: action,
      requestedPowerLevel: requestedPowerLevel,
    );
  }

  Future<void> setRoomMemberPowerLevel({
    required String accountId,
    required String roomId,
    required String userId,
    required int powerLevel,
  }) {
    return accounts.setRoomMemberPowerLevel(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
      powerLevel: powerLevel,
    );
  }

  Future<void> kickRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) {
    return accounts.kickRoomMember(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
    );
  }

  Future<void> banRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
    String? reason,
  }) {
    return accounts.banRoomMember(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
      reason: reason,
    );
  }

  Future<void> unbanRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) {
    return accounts.unbanRoomMember(
      accountId: accountId,
      roomId: roomId,
      userId: userId,
    );
  }

  Future<String> sendTextMessage({
    required String accountId,
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    return accounts.sendTextMessage(
      accountId: accountId,
      roomId: roomId,
      transactionId: transactionId,
      body: body,
      replyToEventId: replyToEventId,
      replacementEventId: replacementEventId,
    );
  }

  Future<String> sendMediaMessage({
    required String accountId,
    required String roomId,
    required String transactionId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required String caption,
    String? replyToEventId,
    bool voiceMessage = false,
    Duration? duration,
    List<double> waveform = const <double>[],
  }) {
    return accounts.sendMediaMessage(
      accountId: accountId,
      roomId: roomId,
      transactionId: transactionId,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
      caption: caption,
      replyToEventId: replyToEventId,
      voiceMessage: voiceMessage,
      duration: duration,
      waveform: waveform,
    );
  }

  Future<bool> removeAccount(String accountId) async {
    final normalizedAccountId = _normalizeAccountId(accountId);
    final removedRuntime = await accounts.removeAccount(normalizedAccountId);
    final removedRegistration =
        _homeservers.remove(normalizedAccountId) != null;
    return removedRuntime || removedRegistration;
  }

  Future<void> dispose() async {
    await accounts.dispose();
    _homeservers.clear();
  }

  MatrixSdkBoundary _buildBoundary(String accountId) {
    final homeserver = _homeservers[accountId];
    if (homeserver == null) {
      throw StateError(
        'Matrix account must be registered after authentication before activation',
      );
    }
    final builder = _boundaryBuilder;
    if (builder != null) return builder(accountId, homeserver);

    return MatrixRustSdkBoundary(
      bridge:
          _nativeBridge ??
          MatrixRustNativeBridge(libraryPath: matrixRustNativeLibraryPath()),
      homeserver: homeserver,
      resolveStoreSecret: _resolveStoreSecret,
      logger: _logger,
      crashReporter: _crashReporter,
    );
  }

  String _requireRegistered(String accountId) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    if (!_homeservers.containsKey(normalizedAccountId)) {
      throw StateError(
        'Matrix account must be registered after authentication before activation',
      );
    }
    return normalizedAccountId;
  }

  static String _normalizeAccountId(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must be non-empty and contain no NUL bytes',
      );
    }
    return normalized;
  }

  static Uri _normalizeHomeserver(Uri homeserver) {
    if (!homeserver.isAbsolute || homeserver.host.isEmpty) {
      throw ArgumentError.value(
        homeserver,
        'homeserver',
        'must be an absolute HTTP(S) URL',
      );
    }
    if (homeserver.scheme != 'https' && homeserver.scheme != 'http') {
      throw ArgumentError.value(
        homeserver,
        'homeserver',
        'must use HTTP or HTTPS',
      );
    }
    if (homeserver.userInfo.isNotEmpty ||
        homeserver.query.isNotEmpty ||
        homeserver.fragment.isNotEmpty ||
        homeserver.toString().contains('\u0000')) {
      throw ArgumentError.value(
        homeserver,
        'homeserver',
        'must not contain credentials, query, fragment, or NUL bytes',
      );
    }
    return homeserver;
  }
}
