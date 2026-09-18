import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:signals/signals.dart';

enum MatrixAppActivity { foreground, background }

enum MatrixNetworkState { online, offline }

abstract interface class MatrixActivityRuntime {
  Future<void> updateActivity(MatrixAppActivity activity);
}

abstract interface class MatrixConnectivityRuntime {
  Future<void> updateNetworkState(MatrixNetworkState state);
}

final class MatrixRuntimeCoordinator
    implements MatrixActivityRuntime, MatrixConnectivityRuntime {
  MatrixRuntimeCoordinator({
    required MatrixEngine engine,
    required void Function(MatrixSyncBatch) applyBatch,
    required bool Function(MatrixPaginationPage) applyPagination,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
  }) : _sync = MatrixSyncCoordinator(engine: engine, applyBatch: applyBatch),
       _pagination = MatrixBackPaginationController(
         engine: engine,
         applyPage: applyPagination,
       ),
       _activity = initialActivity,
       _networkState = initialNetworkState;

  final MatrixSyncCoordinator _sync;
  final MatrixBackPaginationController _pagination;

  MatrixAppActivity _activity;
  MatrixNetworkState _networkState;
  bool _started = false;
  Future<void> _transition = Future<void>.value();

  bool get shouldSync =>
      _started &&
      _activity == MatrixAppActivity.foreground &&
      _networkState == MatrixNetworkState.online;

  bool get isSyncing => _sync.isRunning;

  ReadonlySignal<MatrixSyncState> get syncState => _sync.state;

  ReadonlySignal<MatrixPaginationState> paginationState(String roomId) {
    return _pagination.stateSignal(roomId);
  }

  void resetPagination() {
    _pagination.reset();
  }

  Future<void> onTimelineViewportChanged({
    required String roomId,
    required int oldestVisibleIndex,
    required bool hasMoreHistory,
  }) {
    if (!shouldSync) return Future<void>.value();
    return _pagination.maybePaginate(
      roomId: roomId,
      firstVisibleIndex: oldestVisibleIndex,
      hasMoreHistory: hasMoreHistory,
    );
  }

  Future<void> start() {
    return _enqueueTransition(() async {
      if (_started) {
        await _reconcile();
        return;
      }
      _started = true;
      try {
        await _reconcile();
      } catch (_) {
        _started = false;
        rethrow;
      }
    });
  }

  @override
  Future<void> updateActivity(MatrixAppActivity activity) {
    return _enqueueTransition(() async {
      final stateChanged = _activity != activity;
      _activity = activity;
      if (!stateChanged && shouldSync == _sync.isRunning) return;
      await _reconcile();
    });
  }

  @override
  Future<void> updateNetworkState(MatrixNetworkState state) {
    return _enqueueTransition(() async {
      final stateChanged = _networkState != state;
      _networkState = state;
      if (!stateChanged && shouldSync == _sync.isRunning) return;
      await _reconcile();
    });
  }

  Future<void> stop() {
    return _enqueueTransition(() async {
      if (!_started &&
          !_sync.isRunning &&
          _sync.state.value.phase == MatrixSyncPhase.idle) {
        return;
      }
      _started = false;
      await _reconcile();
    });
  }

  Future<void> _enqueueTransition(Future<void> Function() action) {
    final transition = _transition.then<void>(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _transition = transition.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return transition;
  }

  Future<void> _reconcile() async {
    if (shouldSync) {
      await _sync.start();
    } else {
      _pagination.cancelInFlight();
      await _sync.stop();
    }
  }
}
