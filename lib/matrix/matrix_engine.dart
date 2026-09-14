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

  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = engine.syncBatches.listen(applyBatch);
    await engine.start();
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await engine.stop();
  }
}
