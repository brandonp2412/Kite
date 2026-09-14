import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';

enum MatrixSdkCapability {
  auditedEncryption,
  encryptedPersistentStore,
  slidingSync,
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

abstract interface class MatrixSdkBoundary {
  Set<MatrixSdkCapability> get capabilities;

  Stream<MatrixSyncBatch> get syncBatches;

  Future<void> open(MatrixSdkStoreConfiguration store);

  Future<void> startSync();

  Future<void> stopSync();

  Future<void> paginateBackwards(String roomId);

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
  }) {
    _requireBoundaryCapability(boundary, MatrixSdkCapability.auditedEncryption);
    _requireBoundaryCapability(
      boundary,
      MatrixSdkCapability.encryptedPersistentStore,
    );
    return MatrixBoundaryEngine._(boundary, store);
  }

  MatrixBoundaryEngine._(this._boundary, this._store);

  final MatrixSdkBoundary _boundary;
  final MatrixSdkStoreConfiguration _store;

  bool _opened = false;
  bool _started = false;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _boundary.syncBatches;

  @override
  Future<void> start() async {
    await _ensureOpen();
    if (_started) return;
    await _boundary.startSync();
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    await _boundary.stopSync();
    _started = false;
  }

  @override
  Future<void> paginateBackwards(String roomId) async {
    _requireCapability(MatrixSdkCapability.backPagination);
    await _ensureOpen();
    await _boundary.paginateBackwards(roomId);
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
