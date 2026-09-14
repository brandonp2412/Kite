import 'dart:async';

import 'package:kite/matrix/matrix_models.dart';

abstract interface class MatrixEngine {
  Stream<MatrixSyncBatch> get syncBatches;

  Future<void> start();

  Future<void> stop();

  Future<void> paginateBackwards(String roomId);
}

final class MatrixSyncCoordinator {
  MatrixSyncCoordinator({required this.engine, required this.applyBatch});

  final MatrixEngine engine;
  final void Function(MatrixSyncBatch) applyBatch;
  StreamSubscription<MatrixSyncBatch>? _subscription;

  bool get isRunning => _subscription != null;

  Future<void> start() async {
    if (_subscription != null) return;
    final subscription = engine.syncBatches.listen(applyBatch);
    _subscription = subscription;
    try {
      await engine.start();
    } catch (_) {
      if (identical(_subscription, subscription)) {
        _subscription = null;
      }
      await subscription.cancel();
      rethrow;
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    await subscription.cancel();
    await engine.stop();
  }
}
