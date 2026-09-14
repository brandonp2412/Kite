import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_lifecycle.dart';

void main() {
  group('FileMatrixRestorationStore', () {
    test('round trips non-secret account and navigation state', () async {
      final directory = await Directory.systemTemp.createTemp('kite-restore-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileMatrixRestorationStore(
        File('${directory.path}/state/restoration.json'),
      );
      const snapshot = MatrixRestorationSnapshot(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        eventId: r'$event',
      );

      expect(await store.load(), isNull);
      await store.save(snapshot);
      final restored = await store.load();

      expect(restored?.accountId, snapshot.accountId);
      expect(restored?.roomId, snapshot.roomId);
      expect(restored?.eventId, snapshot.eventId);
    });

    test('rejects malformed persisted state', () async {
      final directory = await Directory.systemTemp.createTemp('kite-restore-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/restoration.json');
      await file.writeAsString('{"roomId":"!room:example.org"}');
      final store = FileMatrixRestorationStore(file);

      await expectLater(store.load(), throwsFormatException);
    });
  });

  group('MatrixLifecycleCoordinator', () {
    test('restores the previous account and navigation state', () async {
      const snapshot = MatrixRestorationSnapshot(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        eventId: r'$event',
      );
      final store = _MemoryStore(snapshot);
      final sync = _FakeSyncPort();
      MatrixRestorationSnapshot? applied;
      final coordinator = MatrixLifecycleCoordinator(
        store: store,
        syncPort: sync,
        currentSnapshot: () => snapshot,
        restoreSnapshot: (value) => applied = value,
      );

      final restored = await coordinator.restoreAfterProcessStart();

      expect(restored, same(snapshot));
      expect(applied, same(snapshot));
      expect(sync.calls, isEmpty);
    });

    test(
      'persists before background sync pause and ignores duplicates',
      () async {
        const snapshot = MatrixRestorationSnapshot(
          accountId: '@alice:example.org',
          roomId: '!room:example.org',
        );
        final events = <String>[];
        final store = _MemoryStore(null, onSave: (_) => events.add('save'));
        final sync = _FakeSyncPort(events: events);
        final coordinator = MatrixLifecycleCoordinator(
          store: store,
          syncPort: sync,
          currentSnapshot: () => snapshot,
          restoreSnapshot: (_) {},
        );

        expect(
          await coordinator.setPhase(MatrixAppLifecyclePhase.background),
          isTrue,
        );
        expect(
          await coordinator.setPhase(MatrixAppLifecyclePhase.background),
          isFalse,
        );

        expect(events, <String>['save', 'background']);
        expect(store.saved, same(snapshot));
        expect(coordinator.phase, MatrixAppLifecyclePhase.background);
      },
    );

    test('serialises fast background and foreground transitions', () async {
      const snapshot = MatrixRestorationSnapshot(
        accountId: '@alice:example.org',
      );
      final saveGate = Completer<void>();
      final events = <String>[];
      final store = _MemoryStore(
        null,
        onSave: (_) async {
          events.add('save-start');
          await saveGate.future;
          events.add('save-end');
        },
      );
      final sync = _FakeSyncPort(events: events);
      final coordinator = MatrixLifecycleCoordinator(
        store: store,
        syncPort: sync,
        currentSnapshot: () => snapshot,
        restoreSnapshot: (_) {},
      );

      final background = coordinator.setPhase(
        MatrixAppLifecyclePhase.background,
      );
      final foreground = coordinator.setPhase(
        MatrixAppLifecyclePhase.foreground,
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>['save-start']);
      saveGate.complete();
      await Future.wait(<Future<bool>>[background, foreground]);

      expect(events, <String>[
        'save-start',
        'save-end',
        'background',
        'foreground',
      ]);
      expect(coordinator.phase, MatrixAppLifecyclePhase.foreground);
    });
  });
}

final class _MemoryStore implements MatrixRestorationStore {
  _MemoryStore(this.loaded, {this.onSave});

  final MatrixRestorationSnapshot? loaded;
  final FutureOr<void> Function(MatrixRestorationSnapshot snapshot)? onSave;
  MatrixRestorationSnapshot? saved;

  @override
  Future<MatrixRestorationSnapshot?> load() async => loaded;

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    saved = snapshot;
    await onSave?.call(snapshot);
  }
}

final class _FakeSyncPort implements MatrixLifecycleSyncPort {
  _FakeSyncPort({List<String>? events}) : _events = events ?? <String>[];

  final List<String> _events;

  List<String> get calls => List<String>.unmodifiable(_events);

  @override
  Future<void> enterBackground() async {
    _events.add('background');
  }

  @override
  Future<void> enterForeground() async {
    _events.add('foreground');
  }
}
