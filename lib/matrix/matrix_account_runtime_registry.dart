import 'dart:async';

import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:kite/matrix/presentation_store.dart';
import 'package:signals/signals.dart';

typedef MatrixSdkBoundaryFactory = MatrixSdkBoundary Function(String accountId);
typedef MatrixPresentationRetryDelay = Future<void> Function(int attempt);

const int _matrixPresentationWriteMaxAttempts = 3;

Future<void> _defaultMatrixPresentationRetryDelay(int attempt) {
  return Future<void>.delayed(Duration(milliseconds: 50 * attempt));
}

final class MatrixAccountRuntimeRegistry {
  MatrixAccountRuntimeRegistry({
    required this.storeRegistry,
    required this.boundaryFactory,
    required MatrixAppActivity initialActivity,
    required MatrixNetworkState initialNetworkState,
    this.presentationStore,
    MatrixPresentationRetryDelay? presentationRetryDelay,
  }) : _activity = initialActivity,
       _networkState = initialNetworkState,
       _presentationRetryDelay =
           presentationRetryDelay ?? _defaultMatrixPresentationRetryDelay;

  final MatrixAccountStoreRegistry storeRegistry;
  final MatrixSdkBoundaryFactory boundaryFactory;
  final MatrixPresentationStore? presentationStore;
  final MatrixPresentationRetryDelay _presentationRetryDelay;
  final Map<String, _MatrixAccountRuntime> _runtimes =
      <String, _MatrixAccountRuntime>{};
  final Map<String, Future<void>> _presentationWrites =
      <String, Future<void>>{};
  final Set<String> _presentationDirty = <String>{};

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

  ReadonlySignal<MatrixSyncState>? get activeSyncState {
    return _activeRuntime?.runtime.syncState;
  }

  ReadonlySignal<MatrixPaginationState>? activePaginationState(String roomId) {
    return _activeRuntime?.runtime.paginationState(roomId);
  }

  Future<void> onTimelineViewportChanged({
    required String roomId,
    required int oldestVisibleIndex,
    required bool hasMoreHistory,
  }) {
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null) return Future<void>.value();
    return active.runtime.onTimelineViewportChanged(
      roomId: roomId,
      oldestVisibleIndex: oldestVisibleIndex,
      hasMoreHistory: hasMoreHistory,
    );
  }

  Future<MatrixPresentationCache> activate(
    String accountId, {
    FutureOr<void> Function()? onActivated,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    return _enqueue<MatrixPresentationCache>(
      () => _activate(
        normalizedAccountId,
        startSync: true,
        onActivated: onActivated,
      ),
    );
  }

  Future<MatrixPresentationCache> activateCached(
    String accountId, {
    FutureOr<void> Function()? onActivated,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    return _enqueue<MatrixPresentationCache>(
      () => _activate(
        normalizedAccountId,
        startSync: false,
        onActivated: onActivated,
      ),
    );
  }

  Future<void> resumeActive() {
    _ensureNotDisposed();
    return _enqueue<void>(() async {
      final active = _activeRuntime;
      if (active != null) {
        await active.runtime.start();
      }
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

  Future<bool> removeAccount(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    _ensureNotDisposed();

    return _enqueue<bool>(() async {
      final runtime = _runtimes[normalizedAccountId];
      if (runtime != null) {
        await runtime.engine.close();
        _runtimes.remove(normalizedAccountId);
      }
      if (activeAccountId.value == normalizedAccountId) {
        activeAccountId.value = null;
      }

      await flushPresentationWrites(normalizedAccountId);
      final presentation = presentationStore;
      if (presentation != null) {
        await presentation.clear(normalizedAccountId);
      }

      final removedStore = storeRegistry.removeAccount(normalizedAccountId);
      return runtime != null || removedStore;
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
      await flushPresentationWrites();

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

  Future<MatrixPresentationCache> _activate(
    String accountId, {
    required bool startSync,
    FutureOr<void> Function()? onActivated,
  }) async {
    final currentId = activeAccountId.value;
    final current = currentId == null ? null : _runtimes[currentId];
    final next = _runtimeFor(accountId);
    await _ensureHydrated(accountId, next);

    if (identical(current, next)) {
      await onActivated?.call();
      if (startSync) {
        await next.runtime.start();
      }
      return next.cache;
    }

    if (current != null) {
      await current.runtime.stop();
    }

    activeAccountId.value = accountId;
    try {
      await onActivated?.call();
      if (startSync) {
        await next.runtime.start();
      }
    } catch (_) {
      activeAccountId.value = currentId;
      if (current != null) {
        await current.runtime.start();
      }
      rethrow;
    }
    return next.cache;
  }

  _MatrixAccountRuntime _runtimeFor(String accountId) {
    final existing = _runtimes[accountId];
    if (existing != null) return existing;

    final cache = MatrixPresentationCache();
    final engine = MatrixBoundaryEngine(
      boundary: boundaryFactory(accountId),
      store: storeRegistry.forAccount(accountId),
      syncConfigurationProvider: () =>
          MatrixSdkSyncConfiguration(resumeFromCursor: cache.lastSyncCursor),
    );
    final runtime = MatrixRuntimeCoordinator(
      engine: engine,
      applyBatch: (batch) {
        cache.applySync(batch);
        if (presentationStore != null) {
          unawaited(_schedulePresentationWrite(accountId, cache));
        }
      },
      applyPagination: (page) {
        cache.applyPagination(page);
        if (presentationStore != null) {
          unawaited(_schedulePresentationWrite(accountId, cache));
        }
      },
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

  Future<void> _ensureHydrated(
    String accountId,
    _MatrixAccountRuntime runtime,
  ) async {
    if (runtime.hydrated) return;
    final snapshot = await presentationStore?.load(accountId);
    if (snapshot != null) {
      runtime.cache.restore(snapshot);
    }
    runtime.hydrated = true;
  }

  Future<void> _schedulePresentationWrite(
    String accountId,
    MatrixPresentationCache cache,
  ) {
    final store = presentationStore;
    if (store == null) return Future<void>.value();

    _presentationDirty.add(accountId);
    final pending = _presentationWrites[accountId];
    if (pending != null) return pending;

    late final Future<void> guarded;
    final write = Future<void>(() async {
      var failureAttempts = 0;
      while (true) {
        await Future<void>.delayed(Duration.zero);
        if (!_presentationDirty.remove(accountId)) return;
        final snapshot = cache.snapshot();
        try {
          await store.save(accountId, snapshot);
          failureAttempts = 0;
        } catch (_) {
          failureAttempts += 1;
          _presentationDirty.add(accountId);
          if (failureAttempts >= _matrixPresentationWriteMaxAttempts) return;
          await _presentationRetryDelay(failureAttempts);
        }
      }
    });
    guarded = write.whenComplete(() {
      if (identical(_presentationWrites[accountId], guarded)) {
        _presentationWrites.remove(accountId);
      }
    });
    _presentationWrites[accountId] = guarded;
    return guarded;
  }

  Future<void> flushPresentationWrites([String? accountId]) async {
    if (accountId != null) {
      final normalizedAccountId = accountId.trim();
      final runtime = _runtimes[normalizedAccountId];
      if (runtime != null && _presentationDirty.contains(normalizedAccountId)) {
        await _schedulePresentationWrite(normalizedAccountId, runtime.cache);
        return;
      }
      final pending = _presentationWrites[normalizedAccountId];
      if (pending != null) await pending;
      return;
    }

    for (final dirtyAccountId in List<String>.of(_presentationDirty)) {
      final runtime = _runtimes[dirtyAccountId];
      if (runtime != null) {
        unawaited(_schedulePresentationWrite(dirtyAccountId, runtime.cache));
      }
    }
    await Future.wait<void>(List<Future<void>>.of(_presentationWrites.values));
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

  static String _normalizeAccountId(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    return normalizedAccountId;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Matrix account runtime registry is disposed');
    }
  }
}

final class _MatrixAccountRuntime {
  _MatrixAccountRuntime({
    required this.engine,
    required this.runtime,
    required this.cache,
  });

  final MatrixBoundaryEngine engine;
  final MatrixRuntimeCoordinator runtime;
  final MatrixPresentationCache cache;
  bool hydrated = false;
}
