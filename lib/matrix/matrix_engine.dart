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
  bool _needsEngineReset = false;

  bool get isRunning => _subscription != null;

  Future<void> start() async {
    if (_subscription != null) return;
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
    late final StreamSubscription<MatrixSyncBatch> subscription;
    subscription = engine.syncBatches.listen(
      (syncBatch) {
        batch(() {
          applyBatch(syncBatch);
          if (identical(_subscription, subscription)) {
            state.value = const MatrixSyncState.running();
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_subscription, subscription)) {
          state.value = MatrixSyncState.failed(error, stackTrace);
        }
      },
      onDone: () {
        if (identical(_subscription, subscription)) {
          _subscription = null;
          _needsEngineReset = true;
          state.value = MatrixSyncState.failed(
            StateError('Matrix sync stream closed unexpectedly'),
            StackTrace.current,
          );
        }
      },
    );
    _subscription = subscription;
    try {
      await engine.start();
      if (identical(_subscription, subscription) &&
          state.value.phase == MatrixSyncPhase.starting) {
        state.value = const MatrixSyncState.running();
      }
    } catch (error, stackTrace) {
      if (identical(_subscription, subscription)) {
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
    _subscription = null;
    await subscription.cancel();
    await engine.stop();
    _needsEngineReset = false;
    state.value = const MatrixSyncState.idle();
  }
}
