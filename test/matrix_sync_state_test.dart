import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:signals/signals.dart';

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

  test('presentation apply failures become recoverable sync state', () async {
    final engine = _StateFakeMatrixEngine();
    final failure = StateError('deterministic presentation failure');
    var failApply = true;
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (_) {
        if (failApply) throw failure;
      },
    );

    await coordinator.start();
    expect(coordinator.isRunning, isTrue);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, same(failure));

    failApply = false;
    engine.emit(
      const MatrixSyncBatch(
        cursor: 'presentation-recovered',
        rooms: <MatrixRoomDelta>[],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.value.phase, MatrixSyncPhase.running);
    expect(coordinator.state.value.error, isNull);

    await coordinator.stop();
    await engine.close();
  });

  test(
    'sync coordinator accepts synchronous on-listen adapter batches',
    () async {
      final engine = _SynchronousOnListenMatrixEngine();
      final applied = <String>[];
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: (batch) => applied.add(batch.cursor),
      );

      await coordinator.start();

      expect(applied, <String>['on-listen']);
      expect(coordinator.isRunning, isTrue);
      expect(coordinator.state.value.phase, MatrixSyncPhase.running);
      expect(engine.startCalls, 1);

      await coordinator.stop();
      expect(coordinator.isRunning, isFalse);
      expect(coordinator.state.value.phase, MatrixSyncPhase.idle);
      await engine.close();
    },
  );

  test('sync batch and running state publish atomically', () async {
    final engine = _StateFakeMatrixEngine();
    final appliedCursor = signal<String?>(null);
    late final MatrixSyncCoordinator coordinator;
    coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (syncBatch) => appliedCursor.value = syncBatch.cursor,
    );
    var effectRuns = 0;
    final dispose = effect(() {
      effectRuns += 1;
      coordinator.state.value;
      appliedCursor.value;
    });
    addTearDown(dispose);

    expect(effectRuns, 1);
    await coordinator.start();

    expect(coordinator.state.value.phase, MatrixSyncPhase.running);
    expect(appliedCursor.value, 'start-1');
    expect(effectRuns, 3);

    await coordinator.stop();
    await engine.close();
  });

  test(
    'runtime exposes leaf sync state across connectivity transitions',
    () async {
      final engine = _StateFakeMatrixEngine();
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: (_) {},
        applyPagination: (_) {},
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );

      expect(runtime.syncState.value.phase, MatrixSyncPhase.idle);

      await runtime.start();
      expect(runtime.syncState.value.phase, MatrixSyncPhase.running);

      await runtime.updateNetworkState(MatrixNetworkState.offline);
      expect(runtime.isSyncing, isFalse);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.idle);
      await runtime.onTimelineViewportChanged(
        roomId: '!room:kite.test',
        oldestVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(engine.paginationCalls, isEmpty);

      await runtime.updateNetworkState(MatrixNetworkState.online);
      expect(runtime.isSyncing, isTrue);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.running);

      expect(
        runtime.paginationState('!room:kite.test').value.phase,
        MatrixPaginationPhase.idle,
      );
      await runtime.onTimelineViewportChanged(
        roomId: '!room:kite.test',
        oldestVisibleIndex: 9,
        hasMoreHistory: true,
      );
      expect(engine.paginationCalls, isEmpty);
      await runtime.onTimelineViewportChanged(
        roomId: '!room:kite.test',
        oldestVisibleIndex: 8,
        hasMoreHistory: true,
      );
      expect(engine.paginationCalls, <String>['!room:kite.test']);
      expect(
        runtime.paginationState('!room:kite.test').value.phase,
        MatrixPaginationPhase.idle,
      );

      final syncError = StateError('runtime sync failure');
      engine.emitError(syncError);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.failed);
      expect(runtime.syncState.value.error, same(syncError));

      engine.emit(
        const MatrixSyncBatch(
          cursor: 'runtime-recovered',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.running);

      await runtime.stop();
      expect(runtime.syncState.value.phase, MatrixSyncPhase.idle);
      await engine.close();
    },
  );

  test(
    'going offline invalidates in-flight pagination before it can apply',
    () async {
      final engine = _DelayedPaginationMatrixEngine();
      final appliedPages = <MatrixPaginationPage>[];
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: (_) {},
        applyPagination: appliedPages.add,
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );

      await runtime.start();
      final pagination = runtime.onTimelineViewportChanged(
        roomId: '!room:kite.test',
        oldestVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(
        runtime.paginationState('!room:kite.test').value.phase,
        MatrixPaginationPhase.loading,
      );

      await runtime.updateNetworkState(MatrixNetworkState.offline);
      expect(
        runtime.paginationState('!room:kite.test').value.phase,
        MatrixPaginationPhase.idle,
      );

      engine.completePagination();
      await pagination;
      expect(appliedPages, isEmpty);

      await runtime.stop();
      await engine.close();
    },
  );

  test(
    'rapid connectivity transitions preserve offline stop before recovery',
    () async {
      final engine = _StateFakeMatrixEngine();
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: (_) {},
        applyPagination: (_) {},
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );

      await runtime.start();
      expect(engine.startCalls, 1);

      final offline = runtime.updateNetworkState(MatrixNetworkState.offline);
      final online = runtime.updateNetworkState(MatrixNetworkState.online);
      await Future.wait<void>(<Future<void>>[offline, online]);

      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
      expect(runtime.isSyncing, isTrue);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.running);

      await runtime.stop();
      await engine.close();
    },
  );

  test(
    'rapid activity transitions preserve background stop before resume',
    () async {
      final engine = _StateFakeMatrixEngine();
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: (_) {},
        applyPagination: (_) {},
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );

      await runtime.start();
      expect(engine.startCalls, 1);

      final background = runtime.updateActivity(MatrixAppActivity.background);
      final foreground = runtime.updateActivity(MatrixAppActivity.foreground);
      await Future.wait<void>(<Future<void>>[background, foreground]);

      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
      expect(runtime.isSyncing, isTrue);
      expect(runtime.syncState.value.phase, MatrixSyncPhase.running);

      await runtime.stop();
      await engine.close();
    },
  );

  test(
    'non-retryable sync errors end the run and reset the engine before restart',
    () async {
      final engine = _StateFakeMatrixEngine();
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: (_) {},
      );

      await coordinator.start();
      expect(coordinator.isRunning, isTrue);
      expect(engine.startCalls, 1);

      final terminal = MatrixNonRetryableSyncException(
        const FormatException('malformed deterministic payload'),
      );
      engine.emitError(terminal);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isRunning, isFalse);
      expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
      expect(coordinator.state.value.error, same(terminal));

      await coordinator.start();
      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
      expect(coordinator.isRunning, isTrue);
      expect(coordinator.state.value.phase, MatrixSyncPhase.running);

      await coordinator.stop();
      await engine.close();
    },
  );

  test('unexpected sync stream closure clears running state', () async {
    final engine = _StateFakeMatrixEngine();
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (_) {},
    );

    await coordinator.start();
    expect(coordinator.isRunning, isTrue);

    await engine.close();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isRunning, isFalse);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, isA<StateError>());

    await coordinator.stop();
    expect(coordinator.state.value.phase, MatrixSyncPhase.idle);
    expect(engine.stopCalls, 1);
  });

  test(
    'unexpected sync stream closure resets the engine before retry',
    () async {
      final engine = _StateFakeMatrixEngine();
      final applied = <String>[];
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: (batch) => applied.add(batch.cursor),
      );

      await coordinator.start();
      expect(engine.startCalls, 1);
      expect(applied, <String>['start-1']);

      await engine.close();
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.value.phase, MatrixSyncPhase.failed);

      await coordinator.start();
      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
      expect(applied, <String>['start-1', 'start-2']);
      expect(coordinator.state.value.phase, MatrixSyncPhase.running);

      await coordinator.stop();
      expect(engine.stopCalls, 2);
      await engine.close();
    },
  );

  test('failed engine stop is observable and reset before restart', () async {
    final engine = _StateFakeMatrixEngine(stopFailuresRemaining: 1);
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (_) {},
    );

    await coordinator.start();
    await expectLater(coordinator.stop(), throwsA(isA<StateError>()));

    expect(coordinator.isRunning, isFalse);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, isA<StateError>());
    expect(engine.stopCalls, 1);

    await coordinator.start();
    expect(engine.stopCalls, 2);
    expect(engine.startCalls, 2);
    expect(coordinator.isRunning, isTrue);
    expect(coordinator.state.value.phase, MatrixSyncPhase.running);

    await coordinator.stop();
    await engine.close();
  });

  test('failed engine start is reset before retry', () async {
    final engine = _StateFakeMatrixEngine(startFailuresRemaining: 1);
    final coordinator = MatrixSyncCoordinator(
      engine: engine,
      applyBatch: (_) {},
    );

    await expectLater(coordinator.start(), throwsA(isA<StateError>()));
    expect(coordinator.isRunning, isFalse);
    expect(coordinator.state.value.phase, MatrixSyncPhase.failed);
    expect(coordinator.state.value.error, isA<StateError>());
    expect(engine.startCalls, 1);
    expect(engine.stopCalls, 1);

    await coordinator.start();
    expect(engine.startCalls, 2);
    expect(engine.stopCalls, 1);
    expect(coordinator.isRunning, isTrue);
    expect(coordinator.state.value.phase, MatrixSyncPhase.running);

    await coordinator.stop();
    await engine.close();
  });

  test(
    'failed start cleanup preserves the start error and retries reset first',
    () async {
      final engine = _StateFakeMatrixEngine(
        startFailuresRemaining: 1,
        stopFailuresRemaining: 1,
      );
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: (_) {},
      );

      Object? failure;
      try {
        await coordinator.start();
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<StateError>());
      expect(failure.toString(), contains('start failure'));
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 1);
      expect(coordinator.state.value.phase, MatrixSyncPhase.failed);

      await coordinator.start();
      expect(engine.stopCalls, 2);
      expect(engine.startCalls, 2);
      expect(coordinator.isRunning, isTrue);
      expect(coordinator.state.value.phase, MatrixSyncPhase.running);

      await coordinator.stop();
      await engine.close();
    },
  );
}

final class _DelayedPaginationMatrixEngine implements MatrixEngine {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);
  Completer<MatrixPaginationPage>? _pagination;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) {
    final pagination = Completer<MatrixPaginationPage>();
    _pagination = pagination;
    return pagination.future;
  }

  void completePagination() {
    _pagination!.complete(
      const MatrixPaginationPage(
        roomId: '!room:kite.test',
        events: <MatrixTimelineEvent>[],
        reachedStart: false,
      ),
    );
    _pagination = null;
  }

  Future<void> close() => _sync.close();
}

final class _SynchronousOnListenMatrixEngine implements MatrixEngine {
  _SynchronousOnListenMatrixEngine() {
    late final StreamController<MatrixSyncBatch> controller;
    controller = StreamController<MatrixSyncBatch>.broadcast(
      sync: true,
      onListen: () {
        controller.add(
          const MatrixSyncBatch(
            cursor: 'on-listen',
            rooms: <MatrixRoomDelta>[],
          ),
        );
      },
    );
    _sync = controller;
  }

  late final StreamController<MatrixSyncBatch> _sync;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    return MatrixPaginationPage(
      roomId: roomId,
      events: const <MatrixTimelineEvent>[],
      reachedStart: true,
    );
  }

  Future<void> close() => _sync.close();
}

final class _StateFakeMatrixEngine implements MatrixEngine {
  _StateFakeMatrixEngine({
    this.startFailuresRemaining = 0,
    this.stopFailuresRemaining = 0,
  });

  StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int startFailuresRemaining;
  int stopFailuresRemaining;
  int startCalls = 0;
  int stopCalls = 0;
  bool _started = false;
  final List<String> paginationCalls = <String>[];

  @override
  Stream<MatrixSyncBatch> get syncBatches {
    if (_sync.isClosed) {
      _sync = StreamController<MatrixSyncBatch>.broadcast(sync: true);
    }
    return _sync.stream;
  }

  @override
  Future<void> start() async {
    if (_started) return;
    startCalls += 1;
    if (startFailuresRemaining > 0) {
      startFailuresRemaining -= 1;
      throw StateError('deterministic start failure');
    }
    _started = true;
    _sync.add(
      MatrixSyncBatch(
        cursor: 'start-$startCalls',
        rooms: const <MatrixRoomDelta>[],
      ),
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (stopFailuresRemaining > 0) {
      stopFailuresRemaining -= 1;
      throw StateError('deterministic stop failure');
    }
    _started = false;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    paginationCalls.add(roomId);
    return MatrixPaginationPage(
      roomId: roomId,
      events: const <MatrixTimelineEvent>[],
      reachedStart: false,
    );
  }

  void emit(MatrixSyncBatch batch) => _sync.add(batch);

  void emitError(Object error) => _sync.addError(error, StackTrace.current);

  Future<void> close() => _sync.close();
}
