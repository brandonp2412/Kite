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
    this.presentationRoomLimit = 200,
    this.presentationTimelineEventLimit = 50,
    MatrixPresentationRetryDelay? presentationRetryDelay,
  }) : assert(presentationRoomLimit > 0),
       assert(presentationTimelineEventLimit > 0),
       _activity = initialActivity,
       _networkState = initialNetworkState,
       _presentationRetryDelay =
           presentationRetryDelay ?? _defaultMatrixPresentationRetryDelay;

  final MatrixAccountStoreRegistry storeRegistry;
  final MatrixSdkBoundaryFactory boundaryFactory;
  final MatrixPresentationStore? presentationStore;
  final int presentationRoomLimit;
  final int presentationTimelineEventLimit;
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

  ReadonlySignal<MatrixPaginationState>? activePaginationState({
    required String accountId,
    required String roomId,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    if (activeAccountId.value != normalizedAccountId) return null;
    return _runtimes[normalizedAccountId]?.runtime.paginationState(roomId);
  }

  Future<MatrixSdkProfileDetails> loadOwnProfile({required String accountId}) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot load a Matrix profile for an inactive account',
    );
    return active.engine.loadOwnProfile();
  }

  Future<MatrixSdkProfileDetails> loadProfile({
    required String accountId,
    required String userId,
  }) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot load a Matrix profile for an inactive account',
    );
    return active.engine.loadProfile(userId);
  }

  Future<void> updateDisplayName({
    required String accountId,
    required String displayName,
  }) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot update a Matrix profile for an inactive account',
    );
    return active.engine.updateDisplayName(displayName);
  }

  Future<void> updateAvatar({
    required String accountId,
    required String? avatarUrl,
  }) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot update a Matrix profile for an inactive account',
    );
    return active.engine.updateAvatar(avatarUrl);
  }

  Future<String> openDirectMessage({
    required String accountId,
    required String userId,
  }) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot open a Matrix conversation for an inactive account',
    );
    return active.engine.openDirectMessage(userId);
  }

  Future<MatrixSdkCreatedRoom> createRoom({
    required String accountId,
    required MatrixSdkRoomCreationRequest request,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<MatrixSdkCreatedRoom>.error(
        StateError('Cannot create a Matrix room for an inactive account'),
      );
    }
    return active.engine.createRoom(request);
  }

  Future<MatrixSdkRoomDetails> roomDetails({
    required String accountId,
    required String roomId,
  }) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot load Matrix room settings for an inactive account',
    );
    return active.engine.roomDetails(roomId);
  }

  Future<void> setRoomName({
    required String accountId,
    required String roomId,
    required String? name,
  }) => _roomSetting(accountId, (engine) => engine.setRoomName(roomId, name));

  Future<void> setRoomTopic({
    required String accountId,
    required String roomId,
    required String? topic,
  }) => _roomSetting(accountId, (engine) => engine.setRoomTopic(roomId, topic));

  Future<void> setRoomAvatar({
    required String accountId,
    required String roomId,
    required String? avatarUrl,
  }) => _roomSetting(
    accountId,
    (engine) => engine.setRoomAvatar(roomId, avatarUrl),
  );

  Future<void> setRoomCanonicalAlias({
    required String accountId,
    required String roomId,
    required String? canonicalAlias,
  }) => _roomSetting(
    accountId,
    (engine) => engine.setRoomCanonicalAlias(roomId, canonicalAlias),
  );

  Future<void> setRoomJoinRule({
    required String accountId,
    required String roomId,
    required String joinRule,
  }) => _roomSetting(
    accountId,
    (engine) => engine.setRoomJoinRule(roomId, joinRule),
  );

  Future<void> enableRoomEncryption({
    required String accountId,
    required String roomId,
  }) =>
      _roomSetting(accountId, (engine) => engine.enableRoomEncryption(roomId));

  Future<void> setRoomHistoryVisibility({
    required String accountId,
    required String roomId,
    required String visibility,
  }) => _roomSetting(
    accountId,
    (engine) => engine.setRoomHistoryVisibility(roomId, visibility),
  );

  Future<void> setRoomNotificationMode({
    required String accountId,
    required String roomId,
    required String mode,
  }) => _roomSetting(
    accountId,
    (engine) => engine.setRoomNotificationMode(roomId, mode),
  );

  Future<void> _roomSetting(
    String accountId,
    Future<void> Function(MatrixBoundaryEngine engine) update,
  ) {
    final active = _requireActiveAccount(
      accountId,
      'Cannot update Matrix room settings for an inactive account',
    );
    return update(active.engine);
  }

  Future<void> reportRoom({
    required String accountId,
    required String roomId,
    String? reason,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<void>.error(
        StateError('Cannot report a Matrix room for an inactive account'),
      );
    }
    return active.engine.reportRoom(roomId, reason: reason);
  }

  Future<void> reportUser({
    required String accountId,
    required String roomId,
    required String userId,
    String? reason,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<void>.error(
        StateError('Cannot report a Matrix user for an inactive account'),
      );
    }
    return active.engine.reportUser(roomId, userId, reason: reason);
  }

  Future<void> leaveRoom({required String accountId, required String roomId}) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<void>.error(
        StateError('Cannot leave a Matrix room for an inactive account'),
      );
    }
    return active.engine.leaveRoom(roomId);
  }

  Future<void> forgetRoom({required String accountId, required String roomId}) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<void>.error(
        StateError('Cannot forget a Matrix room for an inactive account'),
      );
    }
    return active.engine.forgetRoom(roomId);
  }

  Future<void> setRoomFavourite({
    required String accountId,
    required String roomId,
    required bool isFavourite,
  }) async {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      throw StateError('Cannot update a Matrix room for an inactive account');
    }
    await active.engine.setRoomFavourite(roomId, isFavourite);
    final changed = active.cache.updateRoomFavourite(roomId, isFavourite);
    if (changed && presentationStore != null) {
      await _schedulePresentationWrite(normalizedAccountId, active.cache);
    }
  }

  Future<void> respondToRoomInvite({
    required String accountId,
    required String roomId,
    required bool accept,
  }) async {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      throw StateError('Cannot update a Matrix invite for an inactive account');
    }
    await active.engine.respondToRoomInvite(roomId, accept);
    final changed = active.cache.removeInvite(roomId);
    if (changed && presentationStore != null) {
      await _schedulePresentationWrite(normalizedAccountId, active.cache);
    }
  }

  Future<void> markAllRoomsRead({required String accountId}) async {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      throw StateError(
        'Cannot update Matrix read receipts for an inactive account',
      );
    }

    final targets = <({String roomId, String eventId})>[];
    for (final roomId in active.cache.roomOrder.value) {
      final summary = active.cache.roomSummarySignal(roomId).value;
      if (summary == null ||
          (summary.unreadCount == 0 && summary.highlightCount == 0)) {
        continue;
      }
      final timeline = active.cache.timelineSignal(roomId).value;
      final eventId =
          summary.lastEventId ??
          (timeline.isEmpty ? null : timeline.last.eventId);
      if (eventId == null) {
        throw StateError(
          'Cannot mark a Matrix room read without a latest event',
        );
      }
      targets.add((roomId: roomId, eventId: eventId));
    }

    Object? firstFailure;
    StackTrace? firstFailureStackTrace;
    var changed = false;
    for (final target in targets) {
      try {
        await active.engine.markRoomRead(target.roomId, target.eventId);
        changed = active.cache.updateRoomRead(target.roomId) || changed;
      } catch (error, stackTrace) {
        firstFailure ??= error;
        firstFailureStackTrace ??= stackTrace;
      }
    }
    if (changed && presentationStore != null) {
      await _schedulePresentationWrite(normalizedAccountId, active.cache);
    }
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstFailureStackTrace!);
    }
  }

  Future<List<MatrixSdkRoomMember>> roomMembers({
    required String accountId,
    required String roomId,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot load Matrix room members for an inactive account',
    );
    return active.engine.roomMembers(roomId);
  }

  Future<void> inviteRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot invite Matrix room members for an inactive account',
    );
    return active.engine.inviteRoomMember(roomId, userId);
  }

  Future<bool> canModerateRoomMember({
    required String accountId,
    required String roomId,
    required String actorUserId,
    required String targetUserId,
    required MatrixSdkRoomMemberAction action,
    int? requestedPowerLevel,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot inspect Matrix room permissions for an inactive account',
    );
    return active.engine.canModerateRoomMember(
      roomId: roomId,
      actorUserId: actorUserId,
      targetUserId: targetUserId,
      action: action,
      requestedPowerLevel: requestedPowerLevel,
    );
  }

  Future<void> setRoomMemberPowerLevel({
    required String accountId,
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot change Matrix room member roles for an inactive account',
    );
    return active.engine.setRoomMemberPowerLevel(roomId, userId, powerLevel);
  }

  Future<void> kickRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot remove Matrix room members for an inactive account',
    );
    return active.engine.kickRoomMember(roomId, userId);
  }

  Future<void> banRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
    String? reason,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot ban Matrix room members for an inactive account',
    );
    return active.engine.banRoomMember(roomId, userId, reason: reason);
  }

  Future<void> unbanRoomMember({
    required String accountId,
    required String roomId,
    required String userId,
  }) async {
    final active = _requireActiveAccount(
      accountId,
      'Cannot unban Matrix room members for an inactive account',
    );
    return active.engine.unbanRoomMember(roomId, userId);
  }

  Future<String> sendTextMessage({
    required String accountId,
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      return Future<String>.error(
        StateError('Cannot send a Matrix message for an inactive account'),
      );
    }
    return active.engine.sendTextMessage(
      roomId: roomId,
      transactionId: transactionId,
      body: body,
    );
  }

  Future<void> onTimelineViewportChanged({
    required String accountId,
    required String roomId,
    required int oldestVisibleIndex,
    required bool hasMoreHistory,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    if (activeAccountId.value != normalizedAccountId) {
      return Future<void>.value();
    }
    final active = _runtimes[normalizedAccountId];
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
    void Function()? onActivationRolledBack,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    return _enqueue<MatrixPresentationCache>(
      () => _activate(
        normalizedAccountId,
        startSync: true,
        onActivated: onActivated,
        onActivationRolledBack: onActivationRolledBack,
      ),
    );
  }

  Future<MatrixPresentationCache> activateCached(
    String accountId, {
    FutureOr<void> Function()? onActivated,
    void Function()? onActivationRolledBack,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    return _enqueue<MatrixPresentationCache>(
      () => _activate(
        normalizedAccountId,
        startSync: false,
        onActivated: onActivated,
        onActivationRolledBack: onActivationRolledBack,
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

  Future<void> deactivate({FutureOr<void> Function()? onDeactivated}) {
    _ensureNotDisposed();
    return _enqueue<void>(() async {
      final active = _activeRuntime;
      if (active != null) {
        await active.runtime.stop();
      }

      FutureOr<void>? deactivation;
      batch(() {
        activeAccountId.value = null;
        deactivation = onDeactivated?.call();
      });
      await deactivation;
    });
  }

  Future<bool> removeAccount(
    String accountId, {
    FutureOr<void> Function()? onActiveRemoved,
  }) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();

    return _enqueue<bool>(() async {
      final runtime = _runtimes[normalizedAccountId];
      if (runtime != null) {
        try {
          await runtime.runtime.stop();
          await runtime.engine.close();
        } catch (error, stackTrace) {
          if (activeAccountId.value == normalizedAccountId) {
            try {
              await runtime.runtime.start();
            } catch (_) {}
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        _runtimes.remove(normalizedAccountId);
      }
      FutureOr<void>? activeRemoval;
      if (activeAccountId.value == normalizedAccountId) {
        batch(() {
          activeAccountId.value = null;
          activeRemoval = onActiveRemoved?.call();
        });
        await activeRemoval;
      }

      await flushPresentationWrites(normalizedAccountId);
      final presentation = presentationStore;
      if (presentation != null) {
        await presentation.clear(normalizedAccountId);
      }
      _presentationDirty.remove(normalizedAccountId);
      _presentationWrites.remove(normalizedAccountId);

      final removedStore = storeRegistry.removeAccount(normalizedAccountId);
      return runtime != null || removedStore;
    });
  }

  Future<void> dispose() {
    _disposed = true;
    return _enqueue<void>(() async {
      Object? firstFailure;
      StackTrace? firstFailureStackTrace;
      final stoppedAccounts = <String>{};
      final runtimes = List<MapEntry<String, _MatrixAccountRuntime>>.of(
        _runtimes.entries,
      );

      void captureFailure(Object error, StackTrace stackTrace) {
        firstFailure ??= error;
        firstFailureStackTrace ??= stackTrace;
      }

      activeAccountId.value = null;
      for (final entry in runtimes) {
        try {
          await entry.value.runtime.stop();
          stoppedAccounts.add(entry.key);
        } catch (error, stackTrace) {
          captureFailure(error, stackTrace);
        }
      }

      try {
        await flushPresentationWrites();
        if (_presentationDirty.isNotEmpty) {
          captureFailure(
            StateError(
              'Matrix presentation writes remain pending after bounded retries',
            ),
            StackTrace.current,
          );
        }
      } catch (error, stackTrace) {
        captureFailure(error, stackTrace);
      }

      for (final entry in runtimes) {
        if (!stoppedAccounts.contains(entry.key)) continue;
        try {
          await entry.value.engine.close();
          if (!_presentationDirty.contains(entry.key)) {
            _runtimes.remove(entry.key);
          }
        } catch (error, stackTrace) {
          captureFailure(error, stackTrace);
        }
      }

      final failure = firstFailure;
      if (failure != null) {
        Error.throwWithStackTrace(failure, firstFailureStackTrace!);
      }
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
    void Function()? onActivationRolledBack,
  }) async {
    final currentId = activeAccountId.value;
    final current = currentId == null ? null : _runtimes[currentId];
    final nextWasLoaded = _runtimes.containsKey(accountId);
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
      try {
        await current.runtime.stop();
      } catch (error, stackTrace) {
        if (!nextWasLoaded) {
          await _discardFailedNewRuntime(accountId, next);
        }
        try {
          await current.runtime.start();
        } catch (_) {}
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    await next.runtime.updateActivity(_activity);
    await next.runtime.updateNetworkState(_networkState);

    FutureOr<void>? activation;
    Object? synchronousActivationError;
    StackTrace? synchronousActivationStackTrace;
    batch(() {
      activeAccountId.value = accountId;
      try {
        activation = onActivated?.call();
      } catch (error, stackTrace) {
        activeAccountId.value = currentId;
        try {
          onActivationRolledBack?.call();
        } catch (_) {}
        synchronousActivationError = error;
        synchronousActivationStackTrace = stackTrace;
      }
    });

    final synchronousError = synchronousActivationError;
    if (synchronousError != null) {
      if (current != null) {
        try {
          await current.runtime.start();
        } catch (_) {}
      }
      if (!nextWasLoaded) {
        await _discardFailedNewRuntime(accountId, next);
      }
      Error.throwWithStackTrace(
        synchronousError,
        synchronousActivationStackTrace!,
      );
    }

    try {
      await activation;
      if (startSync) {
        await next.runtime.start();
      }
    } catch (error, stackTrace) {
      batch(() {
        activeAccountId.value = currentId;
        try {
          onActivationRolledBack?.call();
        } catch (_) {}
      });
      if (current != null) {
        try {
          await current.runtime.start();
        } catch (_) {}
      }
      if (!nextWasLoaded) {
        await _discardFailedNewRuntime(accountId, next);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return next.cache;
  }

  Future<void> _discardFailedNewRuntime(
    String accountId,
    _MatrixAccountRuntime runtime,
  ) async {
    if (!identical(_runtimes[accountId], runtime)) return;
    final storeWasOpened = runtime.engine.hasOpenedStore;

    try {
      await runtime.runtime.stop();
      await flushPresentationWrites(accountId);
      if (_presentationDirty.contains(accountId)) return;
      await runtime.engine.close();
    } catch (_) {
      return;
    }

    if (!identical(_runtimes[accountId], runtime)) return;
    _runtimes.remove(accountId);
    if (storeWasOpened) {
      storeRegistry.removeAccount(accountId);
    } else {
      storeRegistry.discardUnopenedAccount(accountId);
    }
  }

  _MatrixAccountRuntime _runtimeFor(String accountId) {
    final existing = _runtimes[accountId];
    if (existing != null) return existing;

    final cache = MatrixPresentationCache();
    final storeAlreadyRegistered = storeRegistry.stores.any(
      (configuration) => configuration.accountId == accountId,
    );
    final store = storeRegistry.forAccount(accountId);
    try {
      final engine = MatrixBoundaryEngine(
        boundary: boundaryFactory(accountId),
        store: store,
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
          final changed = cache.applyPagination(page);
          if (changed && presentationStore != null) {
            unawaited(_schedulePresentationWrite(accountId, cache));
          }
          return changed;
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
    } catch (_) {
      if (!storeAlreadyRegistered) {
        storeRegistry.discardUnopenedAccount(accountId);
      }
      rethrow;
    }
  }

  Future<void> _ensureHydrated(
    String accountId,
    _MatrixAccountRuntime runtime,
  ) async {
    if (runtime.hydrated) return;
    try {
      final snapshot = await presentationStore?.load(accountId);
      if (snapshot != null) {
        runtime.cache.restore(snapshot);
      }
    } catch (_) {
      runtime.hydrated = true;
      return;
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
        final snapshot = cache.snapshot(
          roomLimit: presentationRoomLimit,
          timelineEventLimitPerRoom: presentationTimelineEventLimit,
        );
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

  _MatrixAccountRuntime _requireActiveAccount(
    String accountId,
    String failureMessage,
  ) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    _ensureNotDisposed();
    final active = _activeRuntime;
    if (active == null || activeAccountId.value != normalizedAccountId) {
      throw StateError(failureMessage);
    }
    return active;
  }

  static String _normalizeAccountId(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || normalizedAccountId.contains('\u0000')) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must contain a non-empty account id without NUL bytes',
      );
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
