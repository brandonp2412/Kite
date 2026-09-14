import 'dart:async';

import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

typedef MatrixSdkBoundaryFactory = MatrixSdkBoundary Function(String accountId);

final class MatrixAccountRuntimeRegistry {
  MatrixAccountRuntimeRegistry({
    required this.storeRegistry,
    required this.boundaryFactory,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
  }) : _activity = initialActivity,
       _networkState = initialNetworkState;

  final MatrixAccountStoreRegistry storeRegistry;
  final MatrixSdkBoundaryFactory boundaryFactory;
  final Map<String, _MatrixAccountRuntime> _runtimes =
      <String, _MatrixAccountRuntime>{};

  final Signal<String?> activeAccountId = signal<String?>(null);

  MatrixAppActivity _activity;
  MatrixNetworkState _networkState;
  Future<void> _transition = Future<void>.value();
  bool _disposed = false;

  Iterable<String> get loadedAccountIds =>
      List<String>.unmodifiable(_runtimes.keys);

  MatrixPresentationCache? cacheFor(String accountId) {
    return _runtimes[accountId.trim()]?.cache;
  }

  MatrixPresentationCache? get activeCache {
    final accountId = activeAccountId.value;
    return accountId == null ? null : _runtimes[accountId]?.cache;
  }

  Future<MatrixPresentationCache> activate(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    _ensureNotDisposed();

    return _enqueue<MatrixPresentationCache>(() async {
      final currentId = activeAccountId.value;
      final current = currentId == null ? null : _runtimes[currentId];
      final next = _runtimeFor(normalizedAccountId);

      if (identical(current, next)) {
        await next.runtime.start();
        return next.cache;
      }

      if (current != null) {
        await current.runtime.stop();
      }

      try {
        await next.runtime.start();
      } catch (_) {
        if (current != null) {
          await current.runtime.start();
        }
        rethrow;
      }

      activeAccountId.value = normalizedAccountId;
      return next.cache;
    });
  }

  Future<void> updateActivity(MatrixAppActivity activity) {
    _ensureNotDisposed();
    return _enqueue<void>(() async {
      _activity = activity;
      final active = _activeRuntime;
      if (active != null) {
        await active.runtime.updateActivity(activity);
      }
    });
  }

  Future<void> updateNetworkState(MatrixNetworkState networkState) {
    _ensureNotDisposed();
    return _enqueue<void>(() async {
      _networkState = networkState;
      final active = _activeRuntime;
      if (active != null) {
        await active.runtime.updateNetworkState(networkState);
      }
    });
  }

  Future<void> deactivate() {
    _ensureNotDisposed();
    return _enqueue<void>(() async {
      final active = _activeRuntime;
      if (active == null) return;
      await active.runtime.stop();
      activeAccountId.value = null;
    });
  }

  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _disposed = true;
    return _enqueue<void>(() async {
      final active = _activeRuntime;
      if (active != null) {
        await active.runtime.stop();
      }
      activeAccountId.value = null;

      for (final runtime in _runtimes.values) {
        await runtime.engine.close();
      }
      _runtimes.clear();
    });
  }

  _MatrixAccountRuntime? get _activeRuntime {
    final accountId = activeAccountId.value;
    return accountId == null ? null : _runtimes[accountId];
  }

  _MatrixAccountRuntime _runtimeFor(String accountId) {
    final existing = _runtimes[accountId];
    if (existing != null) return existing;

    final cache = MatrixPresentationCache();
    final engine = MatrixBoundaryEngine(
      boundary: boundaryFactory(accountId),
      store: storeRegistry.forAccount(accountId),
    );
    final runtime = MatrixRuntimeCoordinator(
      engine: engine,
      applyBatch: cache.applySync,
      initialActivity: _activity,
      initialNetworkState: _networkState,
    );
    final accountRuntime = _MatrixAccountRuntime(
      engine: engine,
      runtime: runtime,
      cache: cache,
    );
    _runtimes[accountId] = accountRuntime;
    return accountRuntime;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final next = _transition.then<void>(
      (_) async {
        try {
          completer.complete(await action());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace _) async {
        try {
          completer.complete(await action());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Matrix account runtime registry is disposed');
    }
  }
}

final class _MatrixAccountRuntime {
  const _MatrixAccountRuntime({
    required this.engine,
    required this.runtime,
    required this.cache,
  });

  final MatrixBoundaryEngine engine;
  final MatrixRuntimeCoordinator runtime;
  final MatrixPresentationCache cache;
}
