import 'dart:io';

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

  Future<String> sendTextMessage({
    required String accountId,
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    return accounts.sendTextMessage(
      accountId: accountId,
      roomId: roomId,
      transactionId: transactionId,
      body: body,
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
