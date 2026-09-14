import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  test('sync coordinator exposes narrow recoverable sync state', () async {
    final engine = _StateFakeMatrixEngine();
    final applied = <MatrixSyncBatch>[];
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: applied.add,
    );

    expect(coordinator.state.value.phase, MatrixSyncPhase.idle);

    await coordinator.start();
    expect(coordinator.state.value.phase, MatrixSyncPhase.running);
    expect(applied.map((batch) => batch.cursor), <String>['start-1']);

    final syncError = StateError('deterministic sync failure');
    engine.emitError(syncError);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, same(syncError));
    expect(applied.map((batch) => batch.cursor), <String>['start-1']);

    engine.emit(
      const MatrixSyncBatch(cursor: 'recovered', rooms: <MatrixRoomDelta>[]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.value.phase, MatrixSyncPhase.running);
    expect(applied.map((batch) => batch.cursor), <String>[
      'start-1',
      'recovered',
    ]);

    await coordinator.stop();
    expect(coordinator.state.value.phase, MatrixSyncPhase.idle);
    await engine.close();
  });

  test('failed engine start is observable and retryable', () async {
    final engine = _StateFakeMatrixEngine(startFailuresRemaining: 1);
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (_) {},
    );

    await expectLater(coordinator.start(), throwsA(isA<StateError>()));
    expect(coordinator.isRunning, isFalse);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, isA<StateError>());

    await coordinator.start();
    expect(coordinator.isRunning, isTrue);
    expect(coordinator.state.value.phase, MatrixSyncPhase.running);

    await coordinator.stop();
    await engine.close();
  });
}

final class _StateFakeMatrixEngine implements MatrixEngine {
  _StateFakeMatrixEngine({this.startFailuresRemaining = 0});

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int startFailuresRemaining;
  int startCalls = 0;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
    if (startFailuresRemaining > 0) {
      startFailuresRemaining -= 1;
      throw StateError('deterministic start failure');
    }
    _sync.add(
      MatrixSyncBatch(
        cursor: 'start-$startCalls',
        rooms: const <MatrixRoomDelta>[],
      ),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> paginateBackwards(String roomId) async {}

  void emit(MatrixSyncBatch batch) => _sync.add(batch);

  void emitError(Object error) => _sync.addError(error, StackTrace.current);

  Future<void> close() => _sync.close();
}
