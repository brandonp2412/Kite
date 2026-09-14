import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:signals/signals.dart';

enum MatrixAppActivity { foreground, background }

enum MatrixNetworkState { online, offline }

final class MatrixRuntimeCoordinator {
  MatrixRuntimeCoordinator({
    required MatrixEngine engine,
    required void Function(MatrixSyncBatch) applyBatch,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
  }) : _sync = MatrixSyncCoordinator(engine: engine, applyBatch: applyBatch),
       _pagination = MatrixBackPaginationController(engine: engine),
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

  Future<void> start() async {
    if (_started) {
      await _enqueueReconcile();
      return;
    }
    _started = true;
    try {
      await _enqueueReconcile();
    } catch (_) {
      _started = false;
      rethrow;
    }
  }

  Future<void> updateActivity(MatrixAppActivity activity) async {
    final stateChanged = _activity != activity;
    _activity = activity;
    if (!stateChanged && shouldSync == _sync.isRunning) return;
    await _enqueueReconcile();
  }

  Future<void> updateNetworkState(MatrixNetworkState state) async {
    final stateChanged = _networkState != state;
    _networkState = state;
    if (!stateChanged && shouldSync == _sync.isRunning) return;
    await _enqueueReconcile();
  }

  Future<void> stop() async {
    if (!_started && !_sync.isRunning) return;
    _started = false;
    await _enqueueReconcile();
  }

  Future<void> _enqueueReconcile() {
    final reconcile = _transition.then<void>(
      (_) => _reconcile(),
      onError: (Object _, StackTrace _) => _reconcile(),
    );
    _transition = reconcile.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return reconcile;
  }

  Future<void> _reconcile() async {
    if (shouldSync) {
      await _sync.start();
    } else {
      await _sync.stop();
    }
  }
}
