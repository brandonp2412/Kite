import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  test(
    'sync coordinator subscribes before engine start and stops cleanly',
    () async {
      final engine = _FakeMatrixEngine();
      final applied = <MatrixSyncBatch>[];
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: applied.add,
      );

      await coordinator.start();
      await coordinator.start();

      expect(engine.startCalls, 1);
      expect(applied.map((batch) => batch.cursor), <String>['initial']);

      engine.emit(
        const MatrixSyncBatch(cursor: 'next', rooms: <MatrixRoomDelta>[]),
      );
      expect(applied.map((batch) => batch.cursor), <String>['initial', 'next']);

      await coordinator.stop();
      expect(engine.stopCalls, 1);

      engine.emit(
        const MatrixSyncBatch(cursor: 'ignored', rooms: <MatrixRoomDelta>[]),
      );
      expect(applied.map((batch) => batch.cursor), <String>['initial', 'next']);

      await engine.close();
    },
  );
}

final class _FakeMatrixEngine implements MatrixEngine {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
    _sync.add(
      const MatrixSyncBatch(cursor: 'initial', rooms: <MatrixRoomDelta>[]),
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> paginateBackwards(String roomId) async {}

  void emit(MatrixSyncBatch batch) => _sync.add(batch);

  Future<void> close() => _sync.close();
}
