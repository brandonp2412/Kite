import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';

enum MatrixAppActivity { foreground, background }

enum MatrixNetworkState { online, offline }

final class MatrixRuntimeCoordinator {
  MatrixRuntimeCoordinator({
    required MatrixEngine engine,
    required void Function(MatrixSyncBatch) applyBatch,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
  }) : _sync = MatrixSyncCoordinator(engine: engine, applyBatch: applyBatch),
       _activity = initialActivity,
       _networkState = initialNetworkState;

  final MatrixSyncCoordinator _sync;

  MatrixAppActivity _activity;
  MatrixNetworkState _networkState;
  bool _started = false;
  Future<void> _transition = Future<void>.value();

  bool get shouldSync =>
      _started &&
      _activity == MatrixAppActivity.foreground &&
      _networkState == MatrixNetworkState.online;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _enqueueReconcile();
  }

  Future<void> updateActivity(MatrixAppActivity activity) async {
    if (_activity == activity) return;
    _activity = activity;
    await _enqueueReconcile();
  }

  Future<void> updateNetworkState(MatrixNetworkState state) async {
    if (_networkState == state) return;
    _networkState = state;
    await _enqueueReconcile();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _enqueueReconcile();
  }

  Future<void> _enqueueReconcile() {
    _transition = _transition.then((_) => _reconcile());
    return _transition;
  }

  Future<void> _reconcile() async {
    if (shouldSync) {
      await _sync.start();
    } else {
      await _sync.stop();
    }
  }
}
