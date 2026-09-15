import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_store.dart';
import 'package:signals/signals.dart';

void main() {
  test(
    'account switching isolates encrypted stores and keeps cached UI data',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      final aliceCache = await registry.activate('@alice:example.org');
      final aliceBoundary = boundaries['@alice:example.org']!;

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(aliceBoundary.openedStore?.accountId, '@alice:example.org');
      expect(
        aliceBoundary.openedStore?.encryptionKeyId,
        'matrix-key:@alice:example.org',
      );
      expect(
        aliceCache.roomSummarySignal('!alice:example.org').value?.displayName,
        'Alice room',
      );

      final bobCache = await registry.activate('@bob:example.org');
      final bobBoundary = boundaries['@bob:example.org']!;

      expect(aliceBoundary.stopCalls, 1);
      expect(registry.activeAccountId.value, '@bob:example.org');
      expect(bobBoundary.openedStore?.accountId, '@bob:example.org');
      expect(
        bobBoundary.openedStore?.encryptionKeyId,
        'matrix-key:@bob:example.org',
      );
      expect(
        aliceBoundary.openedStore?.storePath,
        isNot(bobBoundary.openedStore?.storePath),
      );
      expect(
        bobCache.roomSummarySignal('!bob:example.org').value?.displayName,
        'Bob room',
      );
      expect(
        registry
            .cacheFor('@alice:example.org')
            ?.roomSummarySignal('!alice:example.org')
            .value
            ?.displayName,
        'Alice room',
      );
      expect(registry.loadedAccountIds, <String>[
        '@alice:example.org',
        '@bob:example.org',
      ]);
    },
  );

  test(
    'invalid account stores fail before allocating an SDK boundary',
    () async {
      var boundaryFactoryCalls = 0;
      final registry = MatrixAccountRuntimeRegistry(
        storeRegistry: MatrixAccountStoreRegistry(
          rootPath: '/data/kite/matrix',
          encryptionKeyIdForAccount: (_) => 'bad-key\u0000suffix',
        ),
        boundaryFactory: (accountId) {
          boundaryFactoryCalls += 1;
          return _FakeAccountBoundary(accountId: accountId);
        },
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );
      addTearDown(registry.dispose);

      await expectLater(
        registry.activate('@alice:example.org'),
        throwsStateError,
      );
      expect(boundaryFactoryCalls, 0);
      expect(registry.loadedAccountIds, isEmpty);
      expect(registry.activeAccountId.value, isNull);

      expect(
        () => registry.activate('@alice:example.org\u0000other'),
        throwsArgumentError,
      );
      expect(boundaryFactoryCalls, 0);
    },
  );

  test(
    'cached account and navigation restoration publish atomically',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);
      final restoredTarget = signal('home');
      var effectRuns = 0;
      final dispose = effect(() {
        effectRuns += 1;
        registry.activeAccountId.value;
        restoredTarget.value;
      });
      addTearDown(dispose);

      expect(effectRuns, 1);
      await registry.activateCached(
        '@alice:example.org',
        onActivated: () => restoredTarget.value = 'room',
      );

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(restoredTarget.value, 'room');
      expect(effectRuns, 2);
    },
  );

  test(
    'account deactivation and navigation reset publish atomically',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);
      final target = signal('room');
      await registry.activateCached('@alice:example.org');

      var effectRuns = 0;
      final dispose = effect(() {
        effectRuns += 1;
        registry.activeAccountId.value;
        target.value;
      });
      addTearDown(dispose);

      expect(effectRuns, 1);
      await registry.deactivate(onDeactivated: () => target.value = 'home');

      expect(registry.activeAccountId.value, isNull);
      expect(target.value, 'home');
      expect(effectRuns, 2);
    },
  );

  test(
    'restored cache is observable before network sync startup completes',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final startGate = Completer<void>();
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{
          '@alice:example.org': MatrixPresentationSnapshot(
            syncCursor: 'persisted-cursor',
            rooms: <MatrixRoomSummary>[
              MatrixRoomSummary(
                roomId: '!alice:example.org',
                displayName: 'Cached Alice room',
                lastActivity: DateTime.utc(2026, 9, 15, 2),
                streamPosition: 0,
              ),
            ],
          ),
        },
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
        startGateFor: '@alice:example.org',
        startGate: startGate,
      );
      addTearDown(registry.dispose);

      final activation = registry.activate('@alice:example.org');
      await Future<void>.delayed(Duration.zero);

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(
        registry.activeCache
            ?.roomSummarySignal('!alice:example.org')
            .value
            ?.displayName,
        'Cached Alice room',
      );
      expect(registry.activeCache?.lastSyncCursor, 'persisted-cursor');
      expect(
        boundaries['@alice:example.org']!
            .lastSyncConfiguration
            ?.resumeFromCursor,
        'persisted-cursor',
      );
      expect(
        boundaries['@alice:example.org']!
            .lastSyncConfiguration
            ?.initialRoomListLimit,
        200,
      );

      startGate.complete();
      final cache = await activation;
      expect(
        cache.roomSummarySignal('!alice:example.org').value?.displayName,
        'Alice room',
      );
      await registry.flushPresentationWrites('@alice:example.org');
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'alice-start-1',
      );
    },
  );

  test('presentation cache load failure falls through to SDK sync', () async {
    final boundaries = <String, _FakeAccountBoundary>{};
    final presentationStore = _MemoryPresentationStore(
      <String, MatrixPresentationSnapshot>{},
    )..failLoadCallsRemaining = 1;
    final registry = _registry(
      boundaries,
      presentationStore: presentationStore,
    );
    addTearDown(registry.dispose);

    final cache = await registry.activate('@alice:example.org');

    expect(presentationStore.loadCalls, 1);
    expect(registry.activeAccountId.value, '@alice:example.org');
    expect(boundaries['@alice:example.org']?.startCalls, 1);
    expect(
      cache.roomSummarySignal('!alice:example.org').value?.displayName,
      'Alice room',
    );

    await registry.deactivate();
    await registry.activate('@alice:example.org');
    expect(presentationStore.loadCalls, 1);
  });

  test(
    'cached timeline paginates while initial sync is still starting',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final startGate = Completer<void>();
      final cachedEvent = MatrixTimelineEvent(
        eventId: r'$cached:example.org',
        roomId: '!alice:example.org',
        senderId: '@alice:example.org',
        type: 'm.room.message',
        originServerTimestamp: DateTime.utc(2026, 9, 15, 2),
        streamPosition: 2,
      );
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{
          '@alice:example.org': MatrixPresentationSnapshot(
            syncCursor: 'persisted-cursor',
            rooms: <MatrixRoomSummary>[
              MatrixRoomSummary(
                roomId: '!alice:example.org',
                displayName: 'Cached Alice room',
                lastActivity: DateTime.utc(2026, 9, 15, 2),
                streamPosition: 2,
              ),
            ],
            timelines: <String, List<MatrixTimelineEvent>>{
              '!alice:example.org': <MatrixTimelineEvent>[cachedEvent],
            },
          ),
        },
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
        startGateFor: '@alice:example.org',
        startGate: startGate,
      );
      addTearDown(registry.dispose);

      final activation = registry.activate('@alice:example.org');
      while (!boundaries.containsKey('@alice:example.org')) {
        await Future<void>.delayed(Duration.zero);
      }
      final boundary = boundaries['@alice:example.org']!;
      while (boundary.startCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final state = registry.activePaginationState(
        accountId: '@alice:example.org',
        roomId: '!alice:example.org',
      )!;
      await registry.onTimelineViewportChanged(
        accountId: '@alice:example.org',
        roomId: '!alice:example.org',
        oldestVisibleIndex: 0,
        hasMoreHistory: true,
      );

      expect(boundary.paginationCalls, <String>['!alice:example.org']);
      expect(state.value.reachedStart, isTrue);
      expect(
        registry.activeCache!
            .timelineSignal('!alice:example.org')
            .value
            .map((event) => event.eventId),
        <String>[r'$older:example.org', r'$cached:example.org'],
      );
      expect(registry.activeCache?.lastSyncCursor, 'persisted-cursor');

      await registry.flushPresentationWrites('@alice:example.org');
      expect(
        presentationStore
            .snapshots['@alice:example.org']!
            .timelines['!alice:example.org']!
            .map((event) => event.eventId),
        <String>[r'$older:example.org', r'$cached:example.org'],
      );

      startGate.complete();
      await activation;
    },
  );

  test('incremental sync mutates only the owning account cache', () async {
    final boundaries = <String, _FakeAccountBoundary>{};
    final registry = _registry(boundaries);
    addTearDown(registry.dispose);

    final aliceCache = await registry.activate('@alice:example.org');
    final aliceOrder = aliceCache.roomOrder.value;
    await registry.activate('@bob:example.org');
    final bobCache = registry.activeCache!;
    final bobOrder = bobCache.roomOrder.value;

    boundaries['@bob:example.org']!.emit(
      MatrixSyncBatch(
        cursor: 'bob-incremental',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!bob:example.org',
            summary: MatrixRoomSummary(
              roomId: '!bob:example.org',
              displayName: 'Bob room renamed',
              lastActivity: DateTime.utc(2026, 9, 15, 4),
              streamPosition: 2,
            ),
          ),
        ],
      ),
    );

    expect(
      bobCache.roomSummarySignal('!bob:example.org').value?.displayName,
      'Bob room renamed',
    );
    expect(bobCache.lastSyncCursor, 'bob-incremental');
    expect(identical(bobCache.roomOrder.value, bobOrder), isTrue);
    expect(identical(aliceCache.roomOrder.value, aliceOrder), isTrue);
    expect(
      aliceCache.roomSummarySignal('!alice:example.org').value?.displayName,
      'Alice room',
    );
  });

  test(
    'stale account viewport updates cannot paginate the newly active account',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.activate('@bob:example.org');
      final bobBoundary = boundaries['@bob:example.org']!;

      expect(
        registry.activePaginationState(
          accountId: '@alice:example.org',
          roomId: '!shared:example.org',
        ),
        isNull,
      );
      final bobState = registry.activePaginationState(
        accountId: '@bob:example.org',
        roomId: '!shared:example.org',
      );
      expect(bobState, isNotNull);

      await registry.onTimelineViewportChanged(
        accountId: '@alice:example.org',
        roomId: '!shared:example.org',
        oldestVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(bobBoundary.paginationCalls, isEmpty);

      await registry.onTimelineViewportChanged(
        accountId: '@bob:example.org',
        roomId: '!shared:example.org',
        oldestVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(bobBoundary.paginationCalls, <String>['!shared:example.org']);
      expect(bobState!.value.reachedStart, isTrue);
    },
  );

  test(
    'partial initial room chunks persist presentation without advancing cursor',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
      );
      addTearDown(registry.dispose);

      final cache = await registry.activate('@alice:example.org');
      await registry.flushPresentationWrites('@alice:example.org');
      expect(cache.lastSyncCursor, 'alice-start-1');

      boundaries['@alice:example.org']!.emit(
        MatrixSyncBatch(
          cursor: 'alice-next',
          commitCursor: false,
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!new:example.org',
              summary: MatrixRoomSummary(
                roomId: '!new:example.org',
                displayName: 'New room',
                lastActivity: DateTime.utc(2026, 9, 15, 4),
                streamPosition: 2,
              ),
            ),
          ],
        ),
      );
      await registry.flushPresentationWrites('@alice:example.org');

      expect(cache.roomSummarySignal('!new:example.org').value, isNotNull);
      expect(cache.lastSyncCursor, 'alice-start-1');
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'alice-start-1',
      );
      expect(
        presentationStore.snapshots['@alice:example.org']?.rooms.any(
          (room) => room.roomId == '!new:example.org',
        ),
        isTrue,
      );

      boundaries['@alice:example.org']!.emit(
        const MatrixSyncBatch(cursor: 'alice-next', rooms: <MatrixRoomDelta>[]),
      );
      await registry.flushPresentationWrites('@alice:example.org');

      expect(cache.lastSyncCursor, 'alice-next');
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'alice-next',
      );
    },
  );

  test(
    'burst sync persistence coalesces to the latest presentation snapshot',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
      );
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.flushPresentationWrites();
      final savesBeforeBurst = presentationStore.saveCalls;
      final boundary = boundaries['@alice:example.org']!;

      for (var index = 1; index <= 3; index += 1) {
        boundary.emit(
          MatrixSyncBatch(
            cursor: 'burst-$index',
            rooms: const <MatrixRoomDelta>[],
          ),
        );
      }

      await registry.flushPresentationWrites();

      expect(presentationStore.saveCalls, savesBeforeBurst + 1);
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'burst-3',
      );
    },
  );

  test(
    'sync arriving during persistence schedules one latest follow-up save',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
      );
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.flushPresentationWrites();
      final savesBefore = presentationStore.saveCalls;
      final boundary = boundaries['@alice:example.org']!;
      final blockedSave = Completer<void>();
      presentationStore.blockNextSave = blockedSave;

      boundary.emit(
        const MatrixSyncBatch(
          cursor: 'in-flight-1',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      while (presentationStore.saveCalls == savesBefore) {
        await Future<void>.delayed(Duration.zero);
      }

      boundary.emit(
        const MatrixSyncBatch(
          cursor: 'in-flight-2',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      boundary.emit(
        const MatrixSyncBatch(
          cursor: 'in-flight-3',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      blockedSave.complete();
      await registry.flushPresentationWrites();

      expect(presentationStore.saveCalls, savesBefore + 2);
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'in-flight-3',
      );
    },
  );

  test(
    'transient presentation save failure retries without another sync',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
        presentationRetryDelay: (_) async {},
      );
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.flushPresentationWrites();
      final savesBefore = presentationStore.saveCalls;
      presentationStore.failSaveCallsRemaining = 1;

      boundaries['@alice:example.org']!.emit(
        const MatrixSyncBatch(
          cursor: 'retry-latest',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      await registry.flushPresentationWrites();

      expect(presentationStore.saveCalls, savesBefore + 2);
      expect(
        presentationStore.snapshots['@alice:example.org']?.syncCursor,
        'retry-latest',
      );
    },
  );

  test('bounded presentation retries leave dirty state recoverable by explicit flush', () async {
    final boundaries = <String, _FakeAccountBoundary>{};
    final presentationStore = _MemoryPresentationStore(
      <String, MatrixPresentationSnapshot>{},
    );
    final registry = _registry(
      boundaries,
      presentationStore: presentationStore,
      presentationRetryDelay: (_) async {},
    );
    addTearDown(registry.dispose);

    await registry.activate('@alice:example.org');
    await registry.flushPresentationWrites();
    final baselineCursor =
        presentationStore.snapshots['@alice:example.org']?.syncCursor;
    final savesBefore = presentationStore.saveCalls;
    presentationStore.failSaveCallsRemaining = 3;

    boundaries['@alice:example.org']!.emit(
      const MatrixSyncBatch(
        cursor: 'persist-after-recovery',
        rooms: <MatrixRoomDelta>[],
      ),
    );
    await registry.flushPresentationWrites();

    expect(presentationStore.saveCalls, savesBefore + 3);
    expect(
      presentationStore.snapshots['@alice:example.org']?.syncCursor,
      baselineCursor,
    );

    await registry.flushPresentationWrites();
    expect(presentationStore.saveCalls, savesBefore + 4);
    expect(
      presentationStore.snapshots['@alice:example.org']?.syncCursor,
      'persist-after-recovery',
    );
  });

  test(
    'synchronous activation callback failure never exposes the failed account',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      final observedAccounts = <String?>[];
      final dispose = effect(() {
        observedAccounts.add(registry.activeAccountId.value);
      });
      addTearDown(dispose);

      await expectLater(
        registry.activateCached(
          '@bob:example.org',
          onActivated: () => throw StateError('navigation restore failed'),
        ),
        throwsStateError,
      );

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(observedAccounts, isNot(contains('@bob:example.org')));
      expect(boundaries['@alice:example.org']!.stopCalls, 1);
      expect(boundaries['@alice:example.org']!.startCalls, 2);
      expect(boundaries['@bob:example.org']!.startCalls, 0);
    },
  );

  test(
    'failed account activation restores the previous account sync and state',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(
        boundaries,
        failStartFor: '@broken:example.org',
      );
      addTearDown(registry.dispose);

      final aliceCache = await registry.activate('@alice:example.org');
      final aliceBoundary = boundaries['@alice:example.org']!;

      await expectLater(
        registry.activate('@broken:example.org'),
        throwsA(isA<StateError>()),
      );

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(registry.activeCache, same(aliceCache));
      expect(aliceBoundary.stopCalls, 1);
      expect(aliceBoundary.startCalls, 2);
      expect(boundaries['@broken:example.org']!.startCalls, 1);
    },
  );

  test(
    'rollback restart failure does not mask the initiating account failure',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(
        boundaries,
        failStartCallsByAccount: <String, Set<int>>{
          '@alice:example.org': <int>{2},
          '@broken:example.org': <int>{1},
        },
      );
      addTearDown(registry.dispose);

      final aliceCache = await registry.activate('@alice:example.org');

      Object? failure;
      try {
        await registry.activate('@broken:example.org');
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<StateError>());
      expect(failure.toString(), contains('@broken:example.org'));
      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(registry.activeCache, same(aliceCache));
      expect(boundaries['@alice:example.org']!.startCalls, 2);
      expect(registry.activeSyncState?.value.phase, MatrixSyncPhase.failed);
    },
  );

  test(
    'foreground and connectivity state gate only active account sync',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      final alice = boundaries['@alice:example.org']!;

      await registry.updateActivity(MatrixAppActivity.background);
      expect(alice.stopCalls, 1);

      await registry.updateNetworkState(MatrixNetworkState.offline);
      await registry.updateActivity(MatrixAppActivity.foreground);
      expect(alice.startCalls, 1);

      await registry.updateNetworkState(MatrixNetworkState.online);
      expect(alice.startCalls, 2);
      expect(alice.syncConfigurations, hasLength(2));
      expect(alice.syncConfigurations.first.resumeFromCursor, isNull);
      expect(alice.syncConfigurations.last.resumeFromCursor, 'alice-start-1');
    },
  );

  test(
    'switching to an inactive account inherits current background activity',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.activate('@bob:example.org');
      await registry.activate('@alice:example.org');
      final bob = boundaries['@bob:example.org']!;
      expect(bob.startCalls, 1);

      await registry.updateActivity(MatrixAppActivity.background);
      await registry.activate('@bob:example.org');

      expect(registry.activeAccountId.value, '@bob:example.org');
      expect(bob.startCalls, 1);
      expect(registry.activeSyncState?.value.phase, MatrixSyncPhase.idle);

      await registry.updateActivity(MatrixAppActivity.foreground);
      expect(bob.startCalls, 2);
    },
  );

  test(
    'switching to an inactive account inherits current offline network state',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final registry = _registry(boundaries);
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.activate('@bob:example.org');
      await registry.activate('@alice:example.org');
      final bob = boundaries['@bob:example.org']!;
      expect(bob.startCalls, 1);

      await registry.updateNetworkState(MatrixNetworkState.offline);
      await registry.activate('@bob:example.org');

      expect(registry.activeAccountId.value, '@bob:example.org');
      expect(bob.startCalls, 1);
      expect(registry.activeSyncState?.value.phase, MatrixSyncPhase.idle);

      await registry.updateNetworkState(MatrixNetworkState.online);
      expect(bob.startCalls, 2);
    },
  );

  test(
    'repeated login logout and account switching releases runtimes and stores',
    () async {
      final stores = MatrixAccountStoreRegistry(
        rootPath: '/data/kite/matrix',
        encryptionKeyIdForAccount: (accountId) => 'matrix-key:$accountId',
      );
      final boundaries = <_FakeAccountBoundary>[];
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = MatrixAccountRuntimeRegistry(
        storeRegistry: stores,
        boundaryFactory: (accountId) {
          final boundary = _FakeAccountBoundary(accountId: accountId);
          boundaries.add(boundary);
          return boundary;
        },
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
        presentationStore: presentationStore,
      );
      addTearDown(registry.dispose);

      for (var cycle = 0; cycle < 12; cycle++) {
        await registry.activate('@alice:example.org');
        await registry.activate('@bob:example.org');

        expect(registry.loadedAccountIds, hasLength(2));
        expect(stores.stores, hasLength(2));

        expect(await registry.removeAccount('@alice:example.org'), isTrue);
        await registry.flushPresentationWrites('@bob:example.org');
        expect(
          presentationStore.snapshots.containsKey('@alice:example.org'),
          isFalse,
        );
        expect(
          presentationStore.snapshots.containsKey('@bob:example.org'),
          isTrue,
        );

        expect(await registry.removeAccount('@bob:example.org'), isTrue);
        expect(registry.loadedAccountIds, isEmpty);
        expect(stores.stores, isEmpty);
        expect(presentationStore.snapshots, isEmpty);
        expect(registry.activeAccountId.value, isNull);
      }

      expect(boundaries, hasLength(24));
      expect(boundaries.every((boundary) => boundary.closeCalls == 1), isTrue);
      expect(
        boundaries.every((boundary) => !boundary.closeHadSyncListener),
        isTrue,
      );
      expect(await registry.removeAccount('@missing:example.org'), isFalse);
    },
  );

  test(
    'account removal clears abandoned presentation dirty state before re-add',
    () async {
      final boundaries = <String, _FakeAccountBoundary>{};
      final presentationStore = _MemoryPresentationStore(
        <String, MatrixPresentationSnapshot>{},
      );
      final registry = _registry(
        boundaries,
        presentationStore: presentationStore,
        presentationRetryDelay: (_) async {},
      );
      addTearDown(registry.dispose);

      await registry.activate('@alice:example.org');
      await registry.flushPresentationWrites('@alice:example.org');
      presentationStore.failSaveCallsRemaining = 3;
      boundaries['@alice:example.org']!.emit(
        const MatrixSyncBatch(
          cursor: 'discard-on-remove',
          rooms: <MatrixRoomDelta>[],
        ),
      );
      await registry.flushPresentationWrites('@alice:example.org');

      presentationStore.failSaveCallsRemaining = 0;
      await registry.removeAccount('@alice:example.org');
      final savesAfterRemoval = presentationStore.saveCalls;

      await registry.activateCached('@alice:example.org');
      await registry.flushPresentationWrites('@alice:example.org');

      expect(presentationStore.saveCalls, savesAfterRemoval);
      expect(presentationStore.snapshots, isEmpty);
    },
  );

  test('dispose retries cleanup after a transient SDK close failure', () async {
    final boundaries = <String, _FakeAccountBoundary>{};
    final registry = _registry(boundaries);

    await registry.activate('@alice:example.org');
    await registry.activate('@bob:example.org');
    boundaries['@alice:example.org']!.closeFailuresRemaining = 1;

    await expectLater(registry.dispose(), throwsStateError);
    expect(registry.activeAccountId.value, isNull);
    expect(registry.loadedAccountIds, hasLength(2));
    expect(
      () => registry.activate('@later:example.org'),
      throwsA(isA<StateError>()),
    );

    await registry.dispose();

    expect(boundaries['@alice:example.org']!.closeCalls, 2);
    expect(boundaries['@bob:example.org']!.closeCalls, 1);
    expect(registry.loadedAccountIds, isEmpty);
  });

  test('dispose closes every loaded SDK boundary exactly once', () async {
    final boundaries = <String, _FakeAccountBoundary>{};
    final registry = _registry(boundaries);

    await registry.activate('@alice:example.org');
    await registry.activate('@bob:example.org');
    await registry.dispose();
    await registry.dispose();

    expect(boundaries['@alice:example.org']!.closeCalls, 1);
    expect(boundaries['@bob:example.org']!.closeCalls, 1);
    expect(registry.activeAccountId.value, isNull);
    expect(registry.loadedAccountIds, isEmpty);
    expect(
      () => registry.activate('@later:example.org'),
      throwsA(isA<StateError>()),
    );
  });
}

MatrixAccountRuntimeRegistry _registry(
  Map<String, _FakeAccountBoundary> boundaries, {
  String? failStartFor,
  MatrixPresentationStore? presentationStore,
  String? startGateFor,
  Completer<void>? startGate,
  MatrixPresentationRetryDelay? presentationRetryDelay,
  Map<String, Set<int>> failStartCallsByAccount = const <String, Set<int>>{},
}) {
  return MatrixAccountRuntimeRegistry(
    storeRegistry: MatrixAccountStoreRegistry(
      rootPath: '/data/kite/matrix',
      encryptionKeyIdForAccount: (accountId) => 'matrix-key:$accountId',
    ),
    boundaryFactory: (accountId) {
      return boundaries.putIfAbsent(
        accountId,
        () => _FakeAccountBoundary(
          accountId: accountId,
          failStart: accountId == failStartFor,
          failStartCalls: failStartCallsByAccount[accountId] ?? const <int>{},
          startGate: accountId == startGateFor ? startGate : null,
        ),
      );
    },
    initialActivity: MatrixAppActivity.foreground,
    initialNetworkState: MatrixNetworkState.online,
    presentationStore: presentationStore,
    presentationRetryDelay: presentationRetryDelay,
  );
}

final class _FakeAccountBoundary implements MatrixSdkBoundary {
  _FakeAccountBoundary({
    required this.accountId,
    this.failStart = false,
    this.failStartCalls = const <int>{},
    this.startGate,
  });

  final String accountId;
  final bool failStart;
  final Set<int> failStartCalls;
  final Completer<void>? startGate;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.incrementalSync,
    MatrixSdkCapability.backPagination,
  };

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixSdkStoreConfiguration? openedStore;
  final List<MatrixSdkSyncConfiguration> syncConfigurations =
      <MatrixSdkSyncConfiguration>[];
  MatrixSdkSyncConfiguration? get lastSyncConfiguration =>
      syncConfigurations.isEmpty ? null : syncConfigurations.last;
  int startCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;
  int closeFailuresRemaining = 0;
  bool closeHadSyncListener = false;
  final List<String> paginationCalls = <String>[];

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openedStore = store;
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) async {
    startCalls += 1;
    syncConfigurations.add(configuration);
    if (failStart || failStartCalls.contains(startCalls)) {
      throw StateError('deterministic start failure for $accountId');
    }
    await startGate?.future;
    final localpart = accountId.substring(1, accountId.indexOf(':'));
    _sync.add(
      MatrixSyncBatch(
        cursor: '$localpart-start-$startCalls',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!$localpart:example.org',
            summary: MatrixRoomSummary(
              roomId: '!$localpart:example.org',
              displayName:
                  '${localpart[0].toUpperCase()}${localpart.substring(1)} room',
              lastActivity: DateTime.utc(2026, 9, 15, 3),
              streamPosition: startCalls,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> stopSync() async {
    stopCalls += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    paginationCalls.add(roomId);
    return MatrixPaginationPage(
      roomId: roomId,
      events: <MatrixTimelineEvent>[
        MatrixTimelineEvent(
          eventId: r'$older:example.org',
          roomId: roomId,
          senderId: '@alice:example.org',
          type: 'm.room.message',
          originServerTimestamp: DateTime.utc(2026, 9, 15, 1),
          streamPosition: 1,
        ),
      ],
      reachedStart: true,
    );
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closeFailuresRemaining > 0) {
      closeFailuresRemaining -= 1;
      throw StateError('deterministic close failure for $accountId');
    }
    closeHadSyncListener = _sync.hasListener;
    if (!_sync.isClosed) {
      await _sync.close();
    }
  }

  void emit(MatrixSyncBatch batch) => _sync.add(batch);
}

final class _MemoryPresentationStore implements MatrixPresentationStore {
  _MemoryPresentationStore(Map<String, MatrixPresentationSnapshot> initial)
    : snapshots = Map<String, MatrixPresentationSnapshot>.of(initial);

  final Map<String, MatrixPresentationSnapshot> snapshots;
  int loadCalls = 0;
  int saveCalls = 0;
  int failLoadCallsRemaining = 0;
  int failSaveCallsRemaining = 0;
  Completer<void>? blockNextSave;

  @override
  Future<void> clear(String accountId) async {
    snapshots.remove(accountId);
  }

  @override
  Future<MatrixPresentationSnapshot?> load(String accountId) async {
    loadCalls += 1;
    if (failLoadCallsRemaining > 0) {
      failLoadCallsRemaining -= 1;
      throw StateError('deterministic presentation load failure');
    }
    return snapshots[accountId];
  }

  @override
  Future<void> save(
    String accountId,
    MatrixPresentationSnapshot snapshot,
  ) async {
    saveCalls += 1;
    if (failSaveCallsRemaining > 0) {
      failSaveCallsRemaining -= 1;
      throw StateError('deterministic presentation save failure');
    }
    final gate = blockNextSave;
    blockNextSave = null;
    if (gate != null) await gate.future;
    snapshots[accountId] = snapshot;
  }
}
