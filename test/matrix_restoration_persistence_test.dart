import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_restoration.dart';

void main() {
  group('FileMatrixRestorationStore', () {
    test(
      'survives process recreation with exact account and event target',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kite-restoration-test-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/matrix/restoration.json');

        final firstProcess = MatrixRestorationCoordinator(
          FileMatrixRestorationStore(file),
        );
        await firstProcess.record(
          accountId: '@alice:example.org',
          navigationTarget: const MatrixNavigationTarget.event(
            '!room:example.org',
            r'$event:example.org',
          ),
        );

        final secondProcess = MatrixRestorationCoordinator(
          FileMatrixRestorationStore(file),
        );
        final restored = await secondProcess.restore();

        expect(restored?.accountId, '@alice:example.org');
        expect(
          restored?.navigationTarget,
          const MatrixNavigationTarget.event(
            '!room:example.org',
            r'$event:example.org',
          ),
        );
      },
    );

    test('recovers the last good state after an interrupted replace', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-restoration-recovery-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/restoration.json');
      final store = FileMatrixRestorationStore(file);
      await store.save(
        const MatrixRestorationSnapshot(
          accountId: '@alice:example.org',
          navigationTarget: MatrixNavigationTarget.room('!before:example.org'),
        ),
      );

      await file.rename('${file.path}.bak');
      await File('${file.path}.tmp').writeAsString('{interrupted');

      expect(
        (await store.load())?.navigationTarget.roomIdOrAlias,
        '!before:example.org',
      );

      await store.save(
        const MatrixRestorationSnapshot(
          accountId: '@alice:example.org',
          navigationTarget: MatrixNavigationTarget.room('!after:example.org'),
        ),
      );
      expect(
        (await store.load())?.navigationTarget.roomIdOrAlias,
        '!after:example.org',
      );
      expect(await File('${file.path}.bak').exists(), isFalse);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });

    test(
      'malformed persisted state falls back without startup failure',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kite-restoration-corrupt-test-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/restoration.json');
        await file.writeAsString('{not-json');

        final store = FileMatrixRestorationStore(file);

        expect(await store.load(), isNull);
      },
    );

    test('rejects persisted targets with empty Matrix identifiers', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-restoration-empty-target-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/restoration.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'accountId': '@alice:example.org',
          'navigationTarget': <String, Object?>{
            'kind': MatrixNavigationKind.room.name,
            'roomIdOrAlias': '',
          },
        }),
      );

      expect(await FileMatrixRestorationStore(file).load(), isNull);
    });
  });

  group('MatrixRestorationCoordinator', () {
    test('normalizes account id before persisting navigation state', () async {
      final store = _MemoryRestorationStore(null);
      final coordinator = MatrixRestorationCoordinator(store);

      await coordinator.record(
        accountId: '  @alice:example.org  ',
        navigationTarget: const MatrixNavigationTarget.home(),
      );

      expect(store.snapshot?.accountId, '@alice:example.org');
    });
  });

  group('MatrixProcessRestorationCoordinator', () {
    test(
      'activates restored account before navigating to previous state',
      () async {
        final store = _MemoryRestorationStore(
          const MatrixRestorationSnapshot(
            accountId: '@work:example.org',
            navigationTarget: MatrixNavigationTarget.room('!room:example.org'),
          ),
        );
        final order = <String>[];
        final coordinator = MatrixProcessRestorationCoordinator(
          restoration: MatrixRestorationCoordinator(store),
          isAccountAvailable: (accountId) => accountId == '@work:example.org',
          activateAccount: (accountId) => order.add('activate:$accountId'),
          navigate: (target) => order.add('navigate:${target.roomIdOrAlias}'),
        );

        expect(await coordinator.restore(), isTrue);
        expect(order, <String>[
          'activate:@work:example.org',
          'navigate:!room:example.org',
        ]);
      },
    );

    test(
      'clears stale restoration without activating a missing account',
      () async {
        final store = _MemoryRestorationStore(
          const MatrixRestorationSnapshot(
            accountId: '@removed:example.org',
            navigationTarget: MatrixNavigationTarget.home(),
          ),
        );
        var activated = false;
        var navigated = false;
        final coordinator = MatrixProcessRestorationCoordinator(
          restoration: MatrixRestorationCoordinator(store),
          isAccountAvailable: (_) => false,
          activateAccount: (_) => activated = true,
          navigate: (_) => navigated = true,
        );

        expect(await coordinator.restore(), isFalse);
        expect(store.snapshot, isNull);
        expect(activated, isFalse);
        expect(navigated, isFalse);
      },
    );
  });

  group('MatrixAccountStoreRegistry', () {
    test(
      'creates stable isolated SDK stores and encryption keys per account',
      () {
        final registry = MatrixAccountStoreRegistry(
          rootPath: '/data/kite/matrix',
          encryptionKeyIdForAccount: (accountId) => 'key:$accountId',
        );

        final alice = registry.forAccount('@alice:example.org');
        final work = registry.forAccount('@alice:work.example');

        expect(registry.forAccount('@alice:example.org'), same(alice));
        expect(alice.storePath, isNot(work.storePath));
        expect(alice.encryptionKeyId, isNot(work.encryptionKeyId));
        expect(alice.storePath, contains('%40alice%3Aexample.org'));
        expect(registry.stores, hasLength(2));
      },
    );

    test('rejects encryption-key reuse between different accounts', () {
      final registry = MatrixAccountStoreRegistry(
        rootPath: '/data/kite/matrix',
        encryptionKeyIdForAccount: (_) => 'shared-key',
      );

      registry.forAccount('@alice:example.org');

      expect(() => registry.forAccount('@bob:example.org'), throwsStateError);
    });

    test('removed accounts do not release encryption-key ownership', () {
      final registry = MatrixAccountStoreRegistry(
        rootPath: '/data/kite/matrix',
        encryptionKeyIdForAccount: (_) => 'shared-key',
      );

      registry.forAccount('@alice:example.org');
      expect(registry.removeAccount('@alice:example.org'), isTrue);
      expect(registry.stores, isEmpty);

      expect(() => registry.forAccount('@bob:example.org'), throwsStateError);
      expect(
        registry.forAccount('@alice:example.org').encryptionKeyId,
        'shared-key',
      );
    });
  });
}

final class _MemoryRestorationStore implements MatrixRestorationStore {
  _MemoryRestorationStore(this.snapshot);

  MatrixRestorationSnapshot? snapshot;

  @override
  Future<void> clear() async {
    snapshot = null;
  }

  @override
  Future<MatrixRestorationSnapshot?> load() async => snapshot;

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
