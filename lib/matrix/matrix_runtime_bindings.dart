import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:signals/signals.dart';

final class MatrixLifecycleBinding with WidgetsBindingObserver {
  MatrixLifecycleBinding(this._runtime, {WidgetsBinding? binding})
    : _binding = binding ?? WidgetsBinding.instance;

  final MatrixActivityRuntime _runtime;
  final WidgetsBinding _binding;
  bool _attached = false;

  bool get isAttached => _attached;

  Future<void> attach() async {
    if (_attached) return;
    _binding.addObserver(this);
    _attached = true;
    try {
      final lifecycleState = _binding.lifecycleState;
      if (lifecycleState != null) {
        await handleLifecycleState(lifecycleState);
      }
    } catch (error, stackTrace) {
      _binding.removeObserver(this);
      _attached = false;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> detach() async {
    if (!_attached) return;
    _binding.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(handleLifecycleState(state));
  }

  Future<void> handleLifecycleState(AppLifecycleState state) {
    return _runtime.updateActivity(mapLifecycleState(state));
  }

  static MatrixAppActivity mapLifecycleState(AppLifecycleState state) {
    return switch (state) {
      AppLifecycleState.resumed ||
      AppLifecycleState.inactive => MatrixAppActivity.foreground,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => MatrixAppActivity.background,
    };
  }
}

final class MatrixSessionExpiryBinding {
  void Function()? _disposeEffect;
  var _generation = 0;
  var _reported = false;

  bool get isAttached => _disposeEffect != null;

  void attach(
    ReadonlySignal<MatrixSyncState>? syncState,
    VoidCallback onExpired,
  ) {
    detach();
    _reported = false;
    if (syncState == null) return;

    final generation = _generation;
    _disposeEffect = effect(() {
      final error = syncState.value.error;
      final expired =
          error is MatrixNonRetryableSyncException &&
          error.cause is MatrixSessionExpiredException;
      if (!expired || _reported) return;
      _reported = true;
      scheduleMicrotask(() {
        if (generation == _generation) onExpired();
      });
    });
  }

  void detach() {
    _generation += 1;
    _reported = false;
    _disposeEffect?.call();
    _disposeEffect = null;
  }
}

final class MatrixConnectivityBinding {
  MatrixConnectivityBinding(this._runtime, this._initialState, this._changes);

  final MatrixConnectivityRuntime _runtime;
  final MatrixNetworkState _initialState;
  final Stream<MatrixNetworkState> _changes;
  StreamSubscription<MatrixNetworkState>? _subscription;

  bool get isAttached => _subscription != null;

  Future<void> attach() async {
    if (_subscription != null) return;

    final initialUpdate = _runtime.updateNetworkState(_initialState);
    late final StreamSubscription<MatrixNetworkState> subscription;
    subscription = _changes.listen((state) {
      unawaited(_runtime.updateNetworkState(state));
    });
    _subscription = subscription;

    try {
      await initialUpdate;
    } catch (error, stackTrace) {
      if (identical(_subscription, subscription)) {
        _subscription = null;
      }
      await subscription.cancel();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> detach() async {
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    await subscription.cancel();
  }
}
