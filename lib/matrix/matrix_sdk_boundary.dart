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
    this.timelineEventLimit = 20,
    this.resumeFromCursor,
  }) : assert(initialRoomListLimit > 0),
       assert(timelineEventLimit > 0);

  final int initialRoomListLimit;
  final int timelineEventLimit;
  final String? resumeFromCursor;
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

  @override
  Stream<MatrixSyncBatch> get syncBatches => _boundary.syncBatches;

  @override
  Future<void> start() async {
    await _ensureOpen();
    if (_started) return;
    await _boundary.startSync(_syncConfigurationProvider());
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    await _boundary.stopSync();
    _started = false;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    _requireCapability(MatrixSdkCapability.backPagination);
    await _ensureOpen();
    return _boundary.paginateBackwards(roomId);
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
