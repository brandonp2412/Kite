import 'dart:async';

import 'package:kite/matrix/matrix_models.dart';
import 'package:signals/signals.dart';

abstract interface class MatrixEngine {
  Stream<MatrixSyncBatch> get syncBatches;

  Future<void> start();

  Future<void> stop();

  Future<MatrixPaginationPage> paginateBackwards(String roomId);
}

enum MatrixSyncPhase { idle, starting, running, failed }

final class MatrixSyncState {
  const MatrixSyncState._(this.phase, this.error, this.stackTrace);

  const MatrixSyncState.idle() : this._(MatrixSyncPhase.idle, null, null);

  const MatrixSyncState.starting()
    : this._(MatrixSyncPhase.starting, null, null);

  const MatrixSyncState.running() : this._(MatrixSyncPhase.running, null, null);

  MatrixSyncState.failed(Object error, StackTrace stackTrace)
    : this._(MatrixSyncPhase.failed, error, stackTrace);

  final MatrixSyncPhase phase;
  final Object? error;
  final StackTrace? stackTrace;
}

final class MatrixSyncCoordinator {
  MatrixSyncCoordinator({required this.engine, required this.applyBatch});

  final MatrixEngine engine;
  final void Function(MatrixSyncBatch) applyBatch;
  final Signal<MatrixSyncState> state = signal<MatrixSyncState>(
    const MatrixSyncState.idle(),
  );
  StreamSubscription<MatrixSyncBatch>? _subscription;
  Object? _activeRun;
  bool _needsEngineReset = false;

  bool get isRunning => _activeRun != null;

  Future<void> start() async {
    if (_activeRun != null) return;
    if (_needsEngineReset) {
      try {
        await engine.stop();
        _needsEngineReset = false;
      } catch (error, stackTrace) {
        state.value = MatrixSyncState.failed(error, stackTrace);
        rethrow;
      }
    }
    state.value = const MatrixSyncState.starting();
    final run = Object();
    _activeRun = run;
    late final StreamSubscription<MatrixSyncBatch> subscription;
    try {
      subscription = engine.syncBatches.listen(
        (syncBatch) {
          if (!identical(_activeRun, run)) return;
          try {
            batch(() {
              applyBatch(syncBatch);
              if (identical(_activeRun, run)) {
                state.value = const MatrixSyncState.running();
              }
            });
          } catch (error, stackTrace) {
            if (identical(_activeRun, run)) {
              state.value = MatrixSyncState.failed(error, stackTrace);
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_activeRun, run)) {
            state.value = MatrixSyncState.failed(error, stackTrace);
          }
        },
        onDone: () {
          if (identical(_activeRun, run)) {
            _activeRun = null;
            _subscription = null;
            _needsEngineReset = true;
            state.value = MatrixSyncState.failed(
              StateError('Matrix sync stream closed unexpectedly'),
              StackTrace.current,
            );
          }
        },
      );
    } catch (error, stackTrace) {
      if (identical(_activeRun, run)) {
        _activeRun = null;
        state.value = MatrixSyncState.failed(error, stackTrace);
      }
      rethrow;
    }

    if (!identical(_activeRun, run)) {
      await subscription.cancel();
      final failure = state.value;
      final error =
          failure.error ?? StateError('Matrix sync stream unavailable');
      Error.throwWithStackTrace(
        error,
        failure.stackTrace ?? StackTrace.current,
      );
    }

    _subscription = subscription;
    try {
      await engine.start();
      if (!identical(_activeRun, run)) {
        final failure = state.value;
        final error =
            failure.error ?? StateError('Matrix sync stream unavailable');
        Error.throwWithStackTrace(
          error,
          failure.stackTrace ?? StackTrace.current,
        );
      }
      if (state.value.phase == MatrixSyncPhase.starting) {
        state.value = const MatrixSyncState.running();
      }
    } catch (error, stackTrace) {
      if (identical(_activeRun, run)) {
        _activeRun = null;
        _subscription = null;
        state.value = MatrixSyncState.failed(error, stackTrace);
      }
      await subscription.cancel();
      rethrow;
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    if (subscription == null) {
      if (state.value.phase != MatrixSyncPhase.idle || _needsEngineReset) {
        await engine.stop();
        _needsEngineReset = false;
        state.value = const MatrixSyncState.idle();
      }
      return;
    }
    _activeRun = null;
    _subscription = null;
    await subscription.cancel();
    await engine.stop();
    _needsEngineReset = false;
    state.value = const MatrixSyncState.idle();
  }
}
