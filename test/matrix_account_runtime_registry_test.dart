import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_store.dart';

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
    'repeated login logout and account switching releases runtimes and stores',
    () async {
      final stores = MatrixAccountStoreRegistry(
        rootPath: '/data/kite/matrix',
        encryptionKeyIdForAccount: (accountId) => 'matrix-key:$accountId',
      );
      final boundaries = <_FakeAccountBoundary>[];
      final registry = MatrixAccountRuntimeRegistry(
        storeRegistry: stores,
        boundaryFactory: (accountId) {
          final boundary = _FakeAccountBoundary(accountId: accountId);
          boundaries.add(boundary);
          return boundary;
        },
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );
      addTearDown(registry.dispose);

      for (var cycle = 0; cycle < 12; cycle++) {
        await registry.activate('@alice:example.org');
        await registry.activate('@bob:example.org');

        expect(registry.loadedAccountIds, hasLength(2));
        expect(stores.stores, hasLength(2));

        expect(await registry.removeAccount('@alice:example.org'), isTrue);
        expect(await registry.removeAccount('@bob:example.org'), isTrue);
        expect(registry.loadedAccountIds, isEmpty);
        expect(stores.stores, isEmpty);
        expect(registry.activeAccountId.value, isNull);
      }

      expect(boundaries, hasLength(24));
      expect(boundaries.every((boundary) => boundary.closeCalls == 1), isTrue);
      expect(await registry.removeAccount('@missing:example.org'), isFalse);
    },
  );

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
          startGate: accountId == startGateFor ? startGate : null,
        ),
      );
    },
    initialActivity: MatrixAppActivity.foreground,
    initialNetworkState: MatrixNetworkState.online,
    presentationStore: presentationStore,
  );
}

final class _FakeAccountBoundary implements MatrixSdkBoundary {
  _FakeAccountBoundary({
    required this.accountId,
    this.failStart = false,
    this.startGate,
  });

  final String accountId;
  final bool failStart;
  final Completer<void>? startGate;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.slidingSync,
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
    if (failStart) throw StateError('deterministic start failure');
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
  Future<void> paginateBackwards(String roomId) async {}

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _sync.close();
  }

  void emit(MatrixSyncBatch batch) => _sync.add(batch);
}

final class _MemoryPresentationStore implements MatrixPresentationStore {
  _MemoryPresentationStore(Map<String, MatrixPresentationSnapshot> initial)
    : snapshots = Map<String, MatrixPresentationSnapshot>.of(initial);

  final Map<String, MatrixPresentationSnapshot> snapshots;

  @override
  Future<void> clear(String accountId) async {
    snapshots.remove(accountId);
  }

  @override
  Future<MatrixPresentationSnapshot?> load(String accountId) async {
    return snapshots[accountId];
  }

  @override
  Future<void> save(
    String accountId,
    MatrixPresentationSnapshot snapshot,
  ) async {
    snapshots[accountId] = snapshot;
  }
}
