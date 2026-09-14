import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_restoration.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/matrix_session_runtime.dart';
import 'package:kite/matrix/presentation_store.dart';

void main() {
  test('process recreation restores account cache and navigation before sync resumes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-runtime-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final presentationStore = FileMatrixPresentationStore(
      Directory('${directory.path}/presentation'),
    );
    final restoration = MatrixRestorationCoordinator(
      FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
    );

    final firstBoundaries = <String, _FakeBoundary>{};
    final firstRegistry = _registry(firstBoundaries, presentationStore);
    final firstSession = MatrixSessionRuntime(
      accounts: firstRegistry,
      restoration: restoration,
      isAccountAvailable: (_) => true,
    );

    await firstSession.activateAccount('@alice:example.org');
    await firstSession.navigate(
      const MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$remember-me:example.org',
      ),
    );
    await firstRegistry.flushPresentationWrites();
    await firstRegistry.dispose();

    final secondBoundaries = <String, _FakeBoundary>{};
    final secondRegistry = _registry(secondBoundaries, presentationStore);
    addTearDown(secondRegistry.dispose);
    final secondSession = MatrixSessionRuntime(
      accounts: secondRegistry,
      restoration: MatrixRestorationCoordinator(
        FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
      ),
      isAccountAvailable: (accountId) => accountId == '@alice:example.org',
    );

    expect(await secondSession.restoreCachedState(), isTrue);
    expect(secondRegistry.activeAccountId.value, '@alice:example.org');
    expect(
      secondSession.navigationTarget.value,
      const MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$remember-me:example.org',
      ),
    );
    expect(
      secondRegistry.activeCache
          ?.roomSummarySignal('!alice:example.org')
          .value
          ?.displayName,
      'Alice room',
    );

    final restoredBoundary = secondBoundaries['@alice:example.org']!;
    expect(restoredBoundary.openCalls, 0);
    expect(restoredBoundary.startCalls, 0);

    await secondSession.resumeSync();

    expect(restoredBoundary.openCalls, 1);
    expect(restoredBoundary.startCalls, 1);
    expect(
      restoredBoundary.lastSyncConfiguration?.resumeFromCursor,
      'alice-start-1',
    );
    expect(secondRegistry.activeCache?.lastSyncCursor, 'alice-start-1');
  });

  test(
    'stale process restoration is cleared without opening an SDK store',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-stale-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      await restorationStore.save(
        const MatrixRestorationSnapshot(
          accountId: '@removed:example.org',
          navigationTarget: MatrixNavigationTarget.room('!old:example.org'),
        ),
      );

      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => false,
      );

      expect(await session.restoreCachedState(), isFalse);
      expect(registry.activeAccountId.value, isNull);
      expect(
        session.navigationTarget.value,
        const MatrixNavigationTarget.home(),
      );
      expect(boundaries, isEmpty);
      expect(await restorationStore.load(), isNull);
    },
  );
}

MatrixAccountRuntimeRegistry _registry(
  Map<String, _FakeBoundary> boundaries,
  MatrixPresentationStore presentationStore,
) {
  return MatrixAccountRuntimeRegistry(
    storeRegistry: MatrixAccountStoreRegistry(
      rootPath: '/data/kite/matrix',
      encryptionKeyIdForAccount: (accountId) => 'matrix-key:$accountId',
    ),
    boundaryFactory: (accountId) =>
        boundaries.putIfAbsent(accountId, () => _FakeBoundary(accountId)),
    initialActivity: MatrixAppActivity.foreground,
    initialNetworkState: MatrixNetworkState.online,
    presentationStore: presentationStore,
  );
}

final class _FakeBoundary implements MatrixSdkBoundary {
  _FakeBoundary(this.accountId);

  final String accountId;
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int openCalls = 0;
  int startCalls = 0;
  MatrixSdkSyncConfiguration? lastSyncConfiguration;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.slidingSync,
    MatrixSdkCapability.backPagination,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openCalls += 1;
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) async {
    startCalls += 1;
    lastSyncConfiguration = configuration;
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
              lastActivity: DateTime.utc(2026, 9, 15, 5),
              streamPosition: startCalls,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> stopSync() async {}

  @override
  Future<void> paginateBackwards(String roomId) async {}

  @override
  Future<void> close() async {
    await _sync.close();
  }
}
