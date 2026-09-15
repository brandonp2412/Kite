import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  final libraryPath = Platform.environment['KITE_MATRIX_BRIDGE_LIBRARY'];

  test('native boundary advertises only implemented SDK capabilities', () {
    final boundary = MatrixRustSdkBoundary(
      bridge: const MatrixRustNativeBridge(libraryPath: '/not-opened'),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'unused',
    );

    expect(boundary.capabilities, <MatrixSdkCapability>{
      MatrixSdkCapability.auditedEncryption,
      MatrixSdkCapability.encryptedPersistentStore,
      MatrixSdkCapability.incrementalSync,
      MatrixSdkCapability.backPagination,
    });
    expect(
      () => MatrixBoundaryEngine(
        boundary: boundary,
        store: const MatrixSdkStoreConfiguration(
          accountId: '@alice:example.org',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
      ),
      returnsNormally,
    );
  });

  test('native bridge rejects an empty store passphrase before FFI', () async {
    final bridge = MatrixRustNativeBridge(
      libraryPath: libraryPath ?? '/unused',
    );

    await expectLater(
      bridge.openEncryptedClient(
        homeserver: Uri.parse('https://matrix.example.org'),
        storePath: '/tmp/kite/alice',
        storePassphrase: '',
      ),
      throwsArgumentError,
    );
  });

  test(
    'SDK boundary coalesces concurrent opens and close waits for opening',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'kite-matrix-boundary-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      var secretResolutions = 0;
      final boundary = MatrixRustSdkBoundary(
        bridge: MatrixRustNativeBridge(libraryPath: libraryPath!),
        homeserver: Uri.parse('http://localhost:8008'),
        resolveStoreSecret: (_) async {
          secretResolutions += 1;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'deterministic-boundary-secret';
        },
      );
      final store = MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '${temp.path}/matrix-sdk',
        encryptionKeyId: 'alice-key',
      );

      final firstOpen = boundary.open(store);
      final secondOpen = boundary.open(store);
      final closing = boundary.close();
      await Future.wait<void>(<Future<void>>[firstOpen, secondOpen, closing]);
      expect(secretResolutions, 1);

      await boundary.open(store);
      expect(secretResolutions, 2);
      await boundary.close();
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );

  test(
    'SDK boundary retries cleanly after an encrypted-store open failure',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'kite-matrix-boundary-retry-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final store = MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '${temp.path}/matrix-sdk',
        encryptionKeyId: 'alice-key',
      );
      final bridge = MatrixRustNativeBridge(libraryPath: libraryPath!);

      final seed = await bridge.openEncryptedClient(
        homeserver: Uri.parse('http://localhost:8008'),
        storePath: store.storePath,
        storePassphrase: 'correct-boundary-secret',
      );
      await seed.close();

      var useWrongSecret = true;
      final boundary = MatrixRustSdkBoundary(
        bridge: bridge,
        homeserver: Uri.parse('http://localhost:8008'),
        resolveStoreSecret: (_) async => useWrongSecret
            ? 'wrong-boundary-secret'
            : 'correct-boundary-secret',
      );

      await expectLater(boundary.open(store), throwsStateError);
      useWrongSecret = false;
      await boundary.open(store);
      await boundary.close();
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );

  test(
    'native boundary streams sync and pagination through Matrix models',
    () async {
      final client = _FakeRustClient();
      final logSink = MemoryStructuredLogSink();
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        logger: StructuredLogger(
          sink: logSink,
          traceIds: SequenceTraceIdGenerator(seed: 100),
        ),
      );
      final batches = <MatrixSyncBatch>[];
      final subscription = boundary.syncBatches.listen(batches.add);
      addTearDown(subscription.cancel);
      addTearDown(boundary.close);

      await boundary.open(
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:example.org',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
      );
      await boundary.startSync(
        const MatrixSdkSyncConfiguration(resumeFromCursor: 'resume-42'),
      );

      await client.firstSyncReturned.future;
      while (batches.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await boundary.stopSync();

      expect(client.syncTimeouts.first, Duration.zero);
      expect(client.syncTokens.first, 'resume-42');
      expect(batches.first.cursor, 'sync-1');
      expect(batches.first.rooms.single.summary!.displayName, 'Native room');
      expect(
        batches.first.rooms.single.timelineEvents.single.eventId,
        r'$event1',
      );

      final page = await boundary.paginateBackwards('!room:kite.test');
      expect(client.paginationCalls, <String>['!room:kite.test']);
      expect(page.roomId, '!room:kite.test');
      expect(page.reachedStart, isTrue);
      expect(page.events.single.eventId, r'$older');
      expect(batches, hasLength(1));
      final timelineLogs = logSink.events
          .where((event) => event.flow == DiagnosticFlow.timeline)
          .toList(growable: false);
      expect(timelineLogs.map((event) => event.event), <DiagnosticEvent>[
        DiagnosticEvent.started,
        DiagnosticEvent.completed,
      ]);
      expect(
        timelineLogs.last.metrics[DiagnosticMetric.itemCount],
        page.events.length,
      );
      expect(
        logSink.events.any(
          (event) =>
              event.flow == DiagnosticFlow.sync &&
              event.event == DiagnosticEvent.completed,
        ),
        isTrue,
      );

      await boundary.close();
      expect(client.isClosed, isTrue);
    },
  );

  test(
    'native boundary retries transient sync failures deterministically',
    () async {
      final client = _RecoveringRustClient();
      final retryDelays = <Duration>[];
      final errors = <Object>[];
      final batches = <MatrixSyncBatch>[];
      final logSink = MemoryStructuredLogSink();
      final crashSink = MemoryCrashReportSink();
      final deferredCrashReporter = _DeferredCrashReporter(
        SanitizingCrashReporter(crashSink),
      );
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        syncRetryDelay: (duration) async {
          retryDelays.add(duration);
        },
        logger: StructuredLogger(
          sink: logSink,
          traceIds: SequenceTraceIdGenerator(seed: 200),
        ),
        crashReporter: deferredCrashReporter,
      );
      final subscription = boundary.syncBatches.listen(
        batches.add,
        onError: (Object error) => errors.add(error),
      );
      addTearDown(subscription.cancel);
      addTearDown(boundary.close);

      await boundary.open(
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:example.org',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
      );
      await boundary.startSync(const MatrixSdkSyncConfiguration());
      await client.recovered.future;
      while (batches.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await boundary.stopSync();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(retryDelays, <Duration>[const Duration(seconds: 1)]);
      expect(batches.first.cursor, 'recovered');
      expect(client.syncCalls, greaterThanOrEqualTo(2));
      final failedLogs = logSink.events
          .where(
            (event) =>
                event.flow == DiagnosticFlow.sync &&
                event.event == DiagnosticEvent.failed,
          )
          .toList(growable: false);
      expect(failedLogs, hasLength(1));
      expect(failedLogs.single.metrics[DiagnosticMetric.attempt], 1);
      expect(crashSink.reports, hasLength(1));
      expect(crashSink.reports.single.errorType, 'StateError');
      expect(crashSink.reports.single.flow, DiagnosticFlow.sync);
      expect(crashSink.reports.single.traceId, failedLogs.single.traceId);
      expect(deferredCrashReporter.release.isCompleted, isFalse);
      deferredCrashReporter.release.complete();
    },
  );

  test(
    'Dart opens and closes a passphrase-encrypted Matrix Rust SDK store off-isolate',
    () async {
      final temp = await Directory.systemTemp.createTemp('kite-matrix-ffi-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final storePath = '${temp.path}/matrix-sdk';
      final bridge = MatrixRustNativeBridge(libraryPath: libraryPath!);

      final client = await bridge.openEncryptedClient(
        homeserver: Uri.parse('http://localhost:8008'),
        storePath: storePath,
        storePassphrase: 'deterministic-🔐-store-secret',
      );

      expect(client.isClosed, isFalse);
      expect(await Directory(storePath).exists(), isTrue);
      await client.close();
      await client.close();
      expect(client.isClosed, isTrue);
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );
}

final class _DeferredCrashReporter implements CrashReporter {
  _DeferredCrashReporter(this.delegate);

  final CrashReporter delegate;
  final Completer<void> release = Completer<void>();

  @override
  Future<void> report(
    Object error, {
    StackTrace? stackTrace,
    required CrashDiagnosticContext context,
  }) async {
    await delegate.report(error, stackTrace: stackTrace, context: context);
    await release.future;
  }
}

final class _FakeRustBridge implements MatrixRustBridge {
  const _FakeRustBridge(this.client);

  final MatrixRustClient client;

  @override
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  }) async {
    return client;
  }
}

final class _RecoveringRustClient implements MatrixRustClient {
  final Completer<void> recovered = Completer<void>();
  int syncCalls = 0;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<String> syncOnce({required Duration timeout, String? since}) async {
    syncCalls += 1;
    if (syncCalls == 1) {
      throw StateError('transient sync failure');
    }
    if (!recovered.isCompleted) recovered.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return '{"cursor":"recovered","rooms":[]}';
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

final class _FakeRustClient implements MatrixRustClient {
  final Completer<void> firstSyncReturned = Completer<void>();
  final List<Duration> syncTimeouts = <Duration>[];
  final List<String?> syncTokens = <String?>[];
  final List<String> paginationCalls = <String>[];

  bool _closed = false;
  int _syncCalls = 0;

  @override
  bool get isClosed => _closed;

  @override
  Future<String> syncOnce({required Duration timeout, String? since}) async {
    syncTimeouts.add(timeout);
    syncTokens.add(since);
    _syncCalls += 1;
    if (_syncCalls == 1) {
      if (!firstSyncReturned.isCompleted) firstSyncReturned.complete();
      return r'''
        {
          "cursor": "sync-1",
          "rooms": [
            {
              "roomId": "!room:kite.test",
              "displayName": "Native room",
              "unreadCount": 1,
              "prevBatch": "back-1",
              "events": [
                {
                  "event_id": "$event1",
                  "sender": "@alice:kite.test",
                  "type": "m.room.message",
                  "origin_server_ts": 2000,
                  "content": {"body": "new"}
                }
              ]
            }
          ]
        }
      ''';
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return '{"cursor":"sync-$_syncCalls","rooms":[]}';
  }

  @override
  Future<String> paginateBackwards({required String roomId}) async {
    paginationCalls.add(roomId);
    return r'''
      {
        "roomId": "!room:kite.test",
        "reachedStart": true,
        "events": [
          {
            "event_id": "$older",
            "sender": "@alice:kite.test",
            "type": "m.room.message",
            "origin_server_ts": 1000,
            "content": {"body": "old"}
          }
        ]
      }
    ''';
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
