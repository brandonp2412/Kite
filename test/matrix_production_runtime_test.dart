import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

      final uploadedMedia = await runtime.uploadMedia(
        accountId: '@alice:example.org',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(uploadedMedia, 'mxc://example.org/uploaded');
      expect(boundary.mediaUploads, hasLength(1));
      expect(boundary.mediaUploads.single.$1, 'image/png');
      expect(boundary.mediaUploads.single.$2, <int>[1, 2, 3, 4]);

      final downloadedMedia = await runtime.downloadMedia(
        accountId: '@alice:example.org',
        contentUri: 'mxc://example.org/avatar',
        width: 384,
        height: 384,
      );
      expect(downloadedMedia, <int>[4, 3, 2, 1]);
      expect(boundary.mediaDownloads, <(String, int, int)>[
        ('mxc://example.org/avatar', 384, 384),
      ]);

      final ownProfile = await runtime.loadOwnProfile(
        accountId: '@alice:example.org',
      );
      final bobProfile = await runtime.loadProfile(
        accountId: '@alice:example.org',
        userId: '@bob:example.org',
      );
      final users = await runtime.searchUsers(
        accountId: '@alice:example.org',
        query: 'bob',
      );
      expect(
        await runtime.loadIgnoredUserIds(accountId: '@alice:example.org'),
        <String>{'@spam:example.org'},
      );
      final devices = await runtime.loadDevices(
        accountId: '@alice:example.org',
      );
      expect(devices, hasLength(2));
      expect(devices.first.deviceId, 'CURRENT');
      expect(devices.first.isCurrent, isTrue);
      expect(devices.first.isVerified, isTrue);
      expect(devices.last.isVerified, isNull);
      await runtime.setUserIgnored(
        accountId: '@alice:example.org',
        userId: '@bob:example.org',
        ignored: true,
      );
      await runtime.updateDisplayName(
        accountId: '@alice:example.org',
        displayName: 'Alice Updated',
      );
      await runtime.updateAvatar(
        accountId: '@alice:example.org',
        avatarUrl: 'mxc://example.org/alice',
      );
      final directRoomId = await runtime.openDirectMessage(
        accountId: '@alice:example.org',
        userId: '@bob:example.org',
      );

      expect(ownProfile.userId, '@alice:example.org');
      expect(ownProfile.displayName, 'Alice');
      expect(bobProfile.userId, '@bob:example.org');
      expect(users.single.userId, '@bob:example.org');
      expect(users.single.avatarUrl, 'mxc://example.org/bob');
      expect(boundary.userSearches, <String>['bob']);
      expect(boundary.ignoredUserWrites, <(String, bool)>[
        ('@bob:example.org', true),
      ]);
      expect(directRoomId, '!dm:example.org');
      expect(boundary.profileMutations, <(String, String?)>[
        ('set_display_name', 'Alice Updated'),
        ('set_avatar', 'mxc://example.org/alice'),
      ]);

      final eventId = await runtime.sendTextMessage(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        transactionId: 'kite-transaction-1',
        body: 'Sent from Kite',
        replyToEventId: r'$original',
      );
      expect(eventId, r'$sent');
      await runtime.sendTextMessage(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        transactionId: 'kite-transaction-2',
        body: 'Edited from Kite',
        replacementEventId: r'$original',
      );
      expect(boundary.sentMessages, <(String, String, String)>[
        ('!room:example.org', 'kite-transaction-1', 'Sent from Kite'),
        ('!room:example.org', 'kite-transaction-2', 'Edited from Kite'),
      ]);
      expect(boundary.sentReplyTargets, <String?>[r'$original', null]);
      expect(boundary.sentReplacementTargets, <String?>[null, r'$original']);

      final mediaEventId = await runtime.sendMediaMessage(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        transactionId: 'kite-media-1',
        filename: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[5, 6, 7]),
        caption: 'Media from Kite',
        replyToEventId: r'$original',
      );
      expect(mediaEventId, r'$media');
      expect(boundary.sentMediaMessages, hasLength(1));
      final sentMedia = boundary.sentMediaMessages.single;
      expect(sentMedia.filename, 'photo.png');
      expect(sentMedia.mimeType, 'image/png');
      expect(sentMedia.bytes, <int>[5, 6, 7]);
      expect(sentMedia.caption, 'Media from Kite');
      expect(sentMedia.replyToEventId, r'$original');

      await runtime.reportEvent(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
        eventId: r'$original',
        reason: 'spam',
      );
      expect(boundary.eventReports, <(String, String, String?)>[
        ('!room:example.org', r'$original', 'spam'),
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

      await runtime.markRoomRead(
        accountId: '@alice:example.org',
        roomId: '!room:example.org',
      );
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

      boundary.emit(
        MatrixSyncBatch(
          cursor: 's2',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!room:example.org',
              summary: MatrixRoomSummary(
                roomId: '!room:example.org',
                displayName: 'Real room',
                lastActivity: DateTime.fromMillisecondsSinceEpoch(
                  1001,
                  isUtc: true,
                ),
                streamPosition: 1001,
                lastEventId: r'$event1',
                unreadCount: 4,
                highlightCount: 1,
              ),
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await runtime.markAllRoomsRead(accountId: '@alice:example.org');
      expect(boundary.readReceipts, <(String, String)>[
        ('!room:example.org', r'$event1'),
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
        MatrixSdkMediaMessageSender,
        MatrixSdkMediaManager,
        MatrixSdkProfileManager,
        MatrixSdkDeviceManager,
        MatrixSdkRoomFavouriteManager,
        MatrixSdkRoomReadManager,
        MatrixSdkTimelineModerationManager {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixSdkStoreConfiguration? openedStore;
  MatrixSdkSyncConfiguration? lastSyncConfiguration;
  int startCount = 0;
  int stopCount = 0;
  int closeCount = 0;
  final List<(String, String, String)> sentMessages =
      <(String, String, String)>[];
  final List<
    ({
      String roomId,
      String transactionId,
      String filename,
      String mimeType,
      List<int> bytes,
      String caption,
      String? replyToEventId,
      bool voiceMessage,
      Duration? duration,
      List<double> waveform,
    })
  >
  sentMediaMessages =
      <
        ({
          String roomId,
          String transactionId,
          String filename,
          String mimeType,
          List<int> bytes,
          String caption,
          String? replyToEventId,
          bool voiceMessage,
          Duration? duration,
          List<double> waveform,
        })
      >[];
  final List<String?> sentReplyTargets = <String?>[];
  final List<String?> sentReplacementTargets = <String?>[];
  final List<(String, bool)> favouriteWrites = <(String, bool)>[];
  final List<(String, String)> readReceipts = <(String, String)>[];
  final List<(String, String, String?)> eventReports =
      <(String, String, String?)>[];
  final List<(String, String?)> profileMutations = <(String, String?)>[];
  final List<String> userSearches = <String>[];
  final Set<String> ignoredUserIds = <String>{'@spam:example.org'};
  final List<(String, bool)> ignoredUserWrites = <(String, bool)>[];
  final List<(String, List<int>)> mediaUploads = <(String, List<int>)>[];
  final List<(String, int, int)> mediaDownloads = <(String, int, int)>[];

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
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  }) async {
    mediaUploads.add((mimeType, List<int>.from(bytes)));
    return 'mxc://example.org/uploaded';
  }

  @override
  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) async {
    mediaDownloads.add((contentUri, width, height));
    return Uint8List.fromList(<int>[4, 3, 2, 1]);
  }

  @override
  Future<MatrixSdkProfileDetails> loadOwnProfile() async {
    return const MatrixSdkProfileDetails(
      userId: '@alice:example.org',
      displayName: 'Alice',
      avatarUrl: 'mxc://example.org/alice-old',
    );
  }

  @override
  Future<MatrixSdkProfileDetails> loadProfile(String userId) async {
    return MatrixSdkProfileDetails(
      userId: userId,
      displayName: userId == '@bob:example.org' ? 'Bob' : null,
      avatarUrl: null,
    );
  }

  @override
  Future<List<MatrixSdkUserSearchResult>> searchUsers(String query) async {
    userSearches.add(query);
    return const <MatrixSdkUserSearchResult>[
      MatrixSdkUserSearchResult(
        userId: '@bob:example.org',
        displayName: 'Bob',
        avatarUrl: 'mxc://example.org/bob',
      ),
    ];
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignoredUserIds};

  @override
  Future<List<MatrixSdkSessionDeviceDetails>> loadDevices() async =>
      <MatrixSdkSessionDeviceDetails>[
        MatrixSdkSessionDeviceDetails(
          deviceId: 'CURRENT',
          isCurrent: true,
          isVerified: true,
          displayName: 'Glass',
          lastSeenAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
        const MatrixSdkSessionDeviceDetails(
          deviceId: 'PHONE',
          isCurrent: false,
          isVerified: null,
          displayName: 'Phone',
        ),
      ];

  @override
  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {}

  @override
  Future<void> setUserIgnored(String userId, bool ignored) async {
    ignoredUserWrites.add((userId, ignored));
    if (ignored) {
      ignoredUserIds.add(userId);
    } else {
      ignoredUserIds.remove(userId);
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    profileMutations.add(('set_display_name', displayName));
  }

  @override
  Future<void> updateAvatar(String? avatarUrl) async {
    profileMutations.add(('set_avatar', avatarUrl));
  }

  @override
  Future<String> openDirectMessage(String userId) async => '!dm:example.org';

  @override
  Future<void> setRoomFavourite(String roomId, bool isFavourite) async {
    favouriteWrites.add((roomId, isFavourite));
  }

  @override
  Future<void> markRoomRead(String roomId, String eventId) async {
    readReceipts.add((roomId, eventId));
  }

  @override
  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) async {
    eventReports.add((roomId, eventId, reason));
  }

  @override
  Future<String> sendMediaMessage({
    required String roomId,
    required String transactionId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required String caption,
    String? replyToEventId,
    bool voiceMessage = false,
    Duration? duration,
    List<double> waveform = const <double>[],
  }) async {
    sentMediaMessages.add((
      roomId: roomId,
      transactionId: transactionId,
      filename: filename,
      mimeType: mimeType,
      bytes: List<int>.of(bytes),
      caption: caption,
      replyToEventId: replyToEventId,
      voiceMessage: voiceMessage,
      duration: duration,
      waveform: List<double>.of(waveform),
    ));
    return r'$media';
  }

  @override
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) async {
    sentMessages.add((roomId, transactionId, body));
    sentReplyTargets.add(replyToEventId);
    sentReplacementTargets.add(replacementEventId);
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
