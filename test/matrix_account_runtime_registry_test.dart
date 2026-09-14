import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

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
        ),
      );
    },
    initialActivity: MatrixAppActivity.foreground,
    initialNetworkState: MatrixNetworkState.online,
  );
}

final class _FakeAccountBoundary implements MatrixSdkBoundary {
  _FakeAccountBoundary({required this.accountId, this.failStart = false});

  final String accountId;
  final bool failStart;

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
  Future<void> startSync() async {
    startCalls += 1;
    if (failStart) throw StateError('deterministic start failure');
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
