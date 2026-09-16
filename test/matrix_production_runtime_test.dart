import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  test(
    'authenticated account activates real runtime composition and lifecycle',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kite-production-runtime-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final boundary = _FakeBoundary();
      String? builtAccountId;
      Uri? builtHomeserver;
      final runtime = MatrixProductionRuntime(
        rootDirectory: root,
        resolveStoreSecret: (_) async => 'production-test-secret',
        encryptionKeyIdForAccount: (accountId) => 'key:$accountId',
        boundaryBuilder: (accountId, homeserver) {
          builtAccountId = accountId;
          builtHomeserver = homeserver;
          return boundary;
        },
      );
      addTearDown(runtime.dispose);

      runtime.registerAuthenticatedAccount(
        accountId: '@alice:example.org',
        homeserver: Uri.parse('https://matrix.example.org'),
      );
      final cache = await runtime.activate('@alice:example.org');

      expect(builtAccountId, '@alice:example.org');
      expect(builtHomeserver, Uri.parse('https://matrix.example.org'));
      expect(boundary.openedStore?.accountId, '@alice:example.org');
      expect(
        boundary.openedStore?.storePath,
        '${root.path}/matrix-sdk/%40alice%3Aexample.org/matrix-sdk',
      );
      expect(boundary.startCount, 1);

      boundary.emit(
        MatrixSyncBatch(
          cursor: 's1',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!room:example.org',
              summary: MatrixRoomSummary(
                roomId: '!room:example.org',
                displayName: 'Real room',
                lastActivity: DateTime.fromMillisecondsSinceEpoch(
                  1000,
                  isUtc: true,
                ),
                streamPosition: 1000,
                lastEventId: r'$event1',
                unreadCount: 2,
                highlightCount: 1,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$event1',
                  roomId: '!room:example.org',
                  senderId: '@bob:example.org',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.fromMillisecondsSinceEpoch(
                    1000,
                    isUtc: true,
                  ),
                  streamPosition: 1000,
                  content: const <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'Hello from Matrix',
                  },
                ),
              ],
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cache.roomOrder.value, <String>['!room:example.org']);
      expect(
        cache.timelineSignal('!room:example.org').value.single.content['body'],
        'Hello from Matrix',
      );
      expect(cache.lastSyncCursor, 's1');

      final eventId = await runtime.sendTextMessage(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        transactionId: 'kite-transaction-1',
        body: 'Sent from Kite',
      );
      expect(eventId, r'$sent');
      expect(boundary.sentMessages, <(String, String, String)>[
        ('!room:example.org', 'kite-transaction-1', 'Sent from Kite'),
      ]);

      await runtime.setRoomFavourite(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        isFavourite: true,
      );
      expect(boundary.favouriteWrites, <(String, bool)>[
        ('!room:example.org', true),
      ]);
      expect(
        cache.roomSummarySignal('!room:example.org').value?.isFavourite,
        isTrue,
      );

      await runtime.markAllRoomsRead(accountId: '@alice:example.org');
      expect(boundary.readReceipts, <(String, String)>[
        ('!room:example.org', r'$event1'),
      ]);
      expect(
        cache.roomSummarySignal('!room:example.org').value?.unreadCount,
        0,
      );
      expect(
        cache.roomSummarySignal('!room:example.org').value?.highlightCount,
        0,
      );

      await runtime.updateActivity(MatrixAppActivity.background);
      expect(boundary.stopCount, 1);
      await runtime.updateActivity(MatrixAppActivity.foreground);
      expect(boundary.startCount, 2);
    },
  );

  test('cached room and timeline state hydrates before sync resumes', () async {
    final root = await Directory.systemTemp.createTemp(
      'kite-production-cache-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final firstBoundary = _FakeBoundary();
    final first = MatrixProductionRuntime(
      rootDirectory: root,
      resolveStoreSecret: (_) async => 'production-test-secret',
      encryptionKeyIdForAccount: (accountId) => 'key:$accountId',
      boundaryBuilder: (_, _) => firstBoundary,
    );
    first.registerAuthenticatedAccount(
      accountId: '@alice:example.org',
      homeserver: Uri.parse('https://matrix.example.org'),
    );
    await first.activate('@alice:example.org');
    firstBoundary.emit(_cachedBatch());
    await Future<void>.delayed(Duration.zero);
    await first.setRoomFavourite(
      accountId: '@alice:example.org',
      roomId: '!cached:example.org',
      isFavourite: true,
    );
    await first.dispose();

    final secondBoundary = _FakeBoundary();
    final second = MatrixProductionRuntime(
      rootDirectory: root,
      resolveStoreSecret: (_) async => 'production-test-secret',
      encryptionKeyIdForAccount: (accountId) => 'key:$accountId',
      boundaryBuilder: (_, _) => secondBoundary,
    );
    addTearDown(second.dispose);
    second.registerAuthenticatedAccount(
      accountId: '@alice:example.org',
      homeserver: Uri.parse('https://matrix.example.org'),
    );

    final cache = await second.activateCached('@alice:example.org');

    expect(secondBoundary.openedStore, isNull);
    expect(secondBoundary.startCount, 0);
    expect(cache.roomOrder.value, <String>['!cached:example.org']);
    expect(
      cache.timelineSignal('!cached:example.org').value.single.content['body'],
      'Cached real message',
    );
    expect(cache.lastSyncCursor, 'cached-s1');
    expect(
      cache.roomSummarySignal('!cached:example.org').value?.isFavourite,
      isTrue,
    );

    await second.resumeActive();
    expect(secondBoundary.openedStore, isNotNull);
    expect(secondBoundary.startCount, 1);
  });

  test(
    'activation requires an authenticated homeserver registration',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kite-production-unregistered-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final runtime = MatrixProductionRuntime(
        rootDirectory: root,
        resolveStoreSecret: (_) async => 'production-test-secret',
        encryptionKeyIdForAccount: (accountId) => 'key:$accountId',
        boundaryBuilder: (_, _) => _FakeBoundary(),
      );
      addTearDown(runtime.dispose);

      expect(() => runtime.activate('@alice:example.org'), throwsStateError);
    },
  );
}

MatrixSyncBatch _cachedBatch() {
  return MatrixSyncBatch(
    cursor: 'cached-s1',
    rooms: <MatrixRoomDelta>[
      MatrixRoomDelta(
        roomId: '!cached:example.org',
        summary: MatrixRoomSummary(
          roomId: '!cached:example.org',
          displayName: 'Cached room',
          lastActivity: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
          streamPosition: 2000,
          lastEventId: r'$cached',
        ),
        timelineEvents: <MatrixTimelineEvent>[
          MatrixTimelineEvent(
            eventId: r'$cached',
            roomId: '!cached:example.org',
            senderId: '@bob:example.org',
            type: 'm.room.message',
            originServerTimestamp: DateTime.fromMillisecondsSinceEpoch(
              2000,
              isUtc: true,
            ),
            streamPosition: 2000,
            content: const <String, Object?>{
              'msgtype': 'm.text',
              'body': 'Cached real message',
            },
          ),
        ],
      ),
    ],
  );
}

final class _FakeBoundary
    implements
        MatrixSdkBoundary,
        MatrixSdkTextMessageSender,
        MatrixSdkRoomFavouriteManager,
        MatrixSdkRoomReadManager {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixSdkStoreConfiguration? openedStore;
  MatrixSdkSyncConfiguration? lastSyncConfiguration;
  int startCount = 0;
  int stopCount = 0;
  int closeCount = 0;
  final List<(String, String, String)> sentMessages =
      <(String, String, String)>[];
  final List<(String, bool)> favouriteWrites = <(String, bool)>[];
  final List<(String, String)> readReceipts = <(String, String)>[];

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.incrementalSync,
    MatrixSdkCapability.backPagination,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openedStore = store;
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) async {
    startCount += 1;
    lastSyncConfiguration = configuration;
  }

  @override
  Future<void> stopSync() async {
    stopCount += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    return MatrixPaginationPage(
      roomId: roomId,
      events: const <MatrixTimelineEvent>[],
      reachedStart: true,
    );
  }

  @override
  Future<void> setRoomFavourite(String roomId, bool isFavourite) async {
    favouriteWrites.add((roomId, isFavourite));
  }

  @override
  Future<void> markRoomRead(String roomId, String eventId) async {
    readReceipts.add((roomId, eventId));
  }

  @override
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
  }) async {
    sentMessages.add((roomId, transactionId, body));
    return r'$sent';
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    await _sync.close();
  }

  void emit(MatrixSyncBatch batch) {
    _sync.add(batch);
  }
}
