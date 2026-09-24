import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
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

  test('recovery work jumps ahead of queued media prefetch', () async {
    final client = _FakeRustClient();
    final prefetchGate = Completer<void>();
    client.prefetchGate = prefetchGate;
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
      codecExecutor: _RecordingCodecExecutor(),
    );
    addTearDown(boundary.close);

    await boundary.open(
      const MatrixSdkStoreConfiguration(
        accountId: '@alice:kite.test',
        storePath: '/tmp/kite/alice-priority',
        encryptionKeyId: 'alice-priority-key',
      ),
    );

    final firstPrefetch = boundary.prefetchMedia(
      contentUris: const <String>['mxc://kite.test/avatar-1'],
      width: 96,
      height: 96,
    );
    await client.prefetchStarted.future;

    final secondPrefetch = boundary.prefetchMedia(
      contentUris: const <String>['mxc://kite.test/avatar-2'],
      width: 96,
      height: 96,
    );
    final recoveryStatus = boundary.encryptionRecoveryStatus();

    prefetchGate.complete();
    await Future.wait<Object?>(<Future<Object?>>[
      firstPrefetch,
      secondPrefetch,
      recoveryStatus,
    ]);

    expect(client.operationOrder, <String>[
      'prefetch-1',
      'recovery-status',
      'prefetch-2',
    ]);
  });

  test(
    'visible media jumps ahead between concurrent prefetch batches',
    () async {
      final client = _FakeRustClient();
      final prefetchGate = Completer<void>();
      client.prefetchGate = prefetchGate;
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: _RecordingCodecExecutor(),
      );
      addTearDown(boundary.close);

      await boundary.open(
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:kite.test',
          storePath: '/tmp/kite/alice-media-priority',
          encryptionKeyId: 'alice-media-priority-key',
        ),
      );

      final prefetch = boundary.prefetchMedia(
        contentUris: const <String>[
          'mxc://kite.test/avatar-1',
          'mxc://kite.test/avatar-2',
          'mxc://kite.test/avatar-3',
          'mxc://kite.test/avatar-4',
          'mxc://kite.test/avatar-5',
          'mxc://kite.test/avatar-6',
          'mxc://kite.test/avatar-7',
          'mxc://kite.test/avatar-8',
        ],
        width: 96,
        height: 96,
      );
      await client.prefetchStarted.future;

      final download = boundary.downloadMedia(
        contentUri: 'mxc://kite.test/visible-image',
        width: 1280,
        height: 1280,
      );

      prefetchGate.complete();
      await Future.wait<Object?>(<Future<Object?>>[prefetch, download]);

      expect(client.operationOrder, <String>[
        'prefetch-1',
        'download-media',
        'prefetch-2',
      ]);
      expect(client.prefetchBatchSizes, [6, 2]);
    },
  );

  test('native boundary exposes Matrix encryption trust state', () async {
    final client = _FakeRustClient();
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
      codecExecutor: _RecordingCodecExecutor(),
    );
    addTearDown(boundary.close);

    await boundary.open(
      const MatrixSdkStoreConfiguration(
        accountId: '@alice:kite.test',
        storePath: '/tmp/kite/alice',
        encryptionKeyId: 'alice-key',
      ),
    );

    expect(
      await boundary.loadCrossSigningTrust(),
      MatrixSdkCrossSigningTrustState.verified,
    );
    final trust = await boundary.loadRoomEncryptionTrust('!room:kite.test');
    expect(trust.roomId, '!room:kite.test');
    expect(trust.isEncrypted, isTrue);
    expect(trust.allDevicesVerified, isTrue);
    expect(client.profileCalls, <(String?, String, String?)>[
      (null, 'cross_signing_trust', null),
    ]);
    expect(client.roomSettingCalls, <(String, String, String?)>[
      ('!room:kite.test', 'get_encryption_trust', null),
    ]);
  });

  test(
    'native boundary routes password login and idempotent text send',
    () async {
      final client = _FakeRustClient();
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: _RecordingCodecExecutor(),
      );
      addTearDown(boundary.close);

      await boundary.open(
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:kite.test',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
      );
      final login = await boundary.loginWithPassword(
        username: '@alice:kite.test',
        password: 'test-password',
      );
      final uploadedMedia = await boundary.uploadMedia(
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final downloadedMedia = await boundary.downloadMedia(
        contentUri: 'mxc://kite.test/avatar',
        width: 384,
        height: 384,
      );
      final ownProfile = await boundary.loadOwnProfile();
      final bobProfile = await boundary.loadProfile('@bob:kite.test');
      final userSearch = await boundary.searchUsers('bo');
      final roomDirectory = await boundary.searchRoomDirectory('kite');
      await boundary.joinRoomFromDirectory('!public:kite.test');
      await boundary.requestRoomJoin('!knock:kite.test');
      final ignoredUserIds = await boundary.loadIgnoredUserIds();
      final devices = await boundary.loadDevices();
      await boundary.signOutDevice('PHONE', password: ' secret with spaces ');
      await boundary.setUserIgnored('@bob:kite.test', true);
      await boundary.updateDisplayName('Alice Updated');
      await boundary.updateAvatar('mxc://kite.test/alice');
      final directRoomId = await boundary.openDirectMessage('@bob:kite.test');
      final eventId = await boundary.sendTextMessage(
        roomId: '!room:kite.test',
        transactionId: 'kite-transaction-1',
        body: 'Hello Matrix',
        replyToEventId: r'$original',
      );
      final editedEventId = await boundary.sendTextMessage(
        roomId: '!room:kite.test',
        transactionId: 'kite-transaction-2',
        body: 'Edited Matrix',
        replacementEventId: r'$original',
      );
      final created = await boundary.createRoom(
        MatrixSdkRoomCreationRequest(
          kind: MatrixSdkRoomCreationKind.privateRoom,
          name: 'Kite room',
          topic: null,
          invitees: const <String>[],
          joinRule: 'invite',
          encryptionEnabled: true,
          historyVisibility: 'joined',
          canonicalAlias: null,
          parentSpaceId: null,
        ),
      );
      await boundary.setSpaceChild(
        spaceId: '!space:kite.test',
        roomId: '!room:kite.test',
        linked: true,
      );
      final roomDetails = await boundary.roomDetails('!room:kite.test');
      await boundary.setRoomName('!room:kite.test', 'Renamed');
      await boundary.setRoomTopic('!room:kite.test', null);
      await boundary.setRoomAvatar('!room:kite.test', 'mxc://kite.test/avatar');
      await boundary.setRoomCanonicalAlias(
        '!room:kite.test',
        '#kite:kite.test',
      );
      await boundary.setRoomJoinRule('!room:kite.test', 'public');
      await boundary.enableRoomEncryption('!room:kite.test');
      await boundary.setRoomHistoryVisibility('!room:kite.test', 'shared');
      await boundary.setRoomNotificationMode('!room:kite.test', 'mentionsOnly');
      await boundary.setRoomFavourite('!room:kite.test', true);
      await boundary.respondToRoomInvite('!invite:kite.test', true);
      await boundary.inviteRoomMember('!room:kite.test', '@bob:kite.test');
      expect(
        await boundary.canModerateRoomMember(
          roomId: '!room:kite.test',
          actorUserId: '@alice:kite.test',
          targetUserId: '@bob:kite.test',
          action: MatrixSdkRoomMemberAction.changePowerLevel,
          requestedPowerLevel: 50,
        ),
        isTrue,
      );
      expect(
        await boundary.canModerateRoomMember(
          roomId: '!room:kite.test',
          actorUserId: '@alice:kite.test',
          targetUserId: '@bob:kite.test',
          action: MatrixSdkRoomMemberAction.changePowerLevel,
          requestedPowerLevel: 100,
        ),
        isFalse,
      );
      await boundary.setRoomMemberPowerLevel(
        '!room:kite.test',
        '@bob:kite.test',
        50,
      );
      await boundary.kickRoomMember('!room:kite.test', '@bob:kite.test');
      await boundary.banRoomMember(
        '!room:kite.test',
        '@bob:kite.test',
        reason: 'spam',
      );
      await boundary.unbanRoomMember('!room:kite.test', '@bob:kite.test');
      await boundary.reportEvent(
        '!room:kite.test',
        r'$abusive:kite.test',
        reason: 'spam event',
      );
      await boundary.redactEvent(
        '!room:kite.test',
        r'$sent',
        transactionId: 'kite-redact-1',
      );
      await boundary.reportRoom('!room:kite.test', reason: 'spam room');
      await boundary.reportUser(
        '!room:kite.test',
        '@bob:kite.test',
        reason: 'spam user',
      );
      await boundary.leaveRoom('!room:kite.test');
      await boundary.forgetRoom('!room:kite.test');
      await boundary.markRoomRead('!room:kite.test', r'$event');

      expect(login.userId, '@alice:kite.test');
      expect(login.deviceId, 'KITEDEVICE');
      expect(uploadedMedia, 'mxc://kite.test/uploaded-media');
      expect(client.mediaUploads, hasLength(1));
      expect(client.mediaUploads.single.$1, 'image/png');
      expect(client.mediaUploads.single.$2, <int>[1, 2, 3]);
      expect(downloadedMedia, <int>[4, 3, 2, 1]);
      expect(client.mediaDownloads, <(String, int, int)>[
        ('mxc://kite.test/avatar', 384, 384),
      ]);
      expect(ownProfile.userId, '@alice:kite.test');
      expect(ownProfile.displayName, 'Alice');
      expect(ownProfile.avatarUrl, 'mxc://kite.test/alice-old');
      expect(bobProfile.userId, '@bob:kite.test');
      expect(bobProfile.displayName, 'Bob');
      expect(userSearch.single.userId, '@bob:kite.test');
      expect(userSearch.single.displayName, 'Bob');
      expect(userSearch.single.avatarUrl, 'mxc://kite.test/bob');
      expect(roomDirectory.single.roomId, '!public:kite.test');
      expect(roomDirectory.single.name, 'Kite Community');
      expect(roomDirectory.single.canonicalAlias, '#kite:kite.test');
      expect(roomDirectory.single.joinRule, 'public');
      expect(roomDirectory.single.worldReadable, isTrue);
      expect(roomDirectory.single.joinedMembers, 42);
      expect(ignoredUserIds, <String>{'@spam:kite.test'});
      expect(devices, hasLength(2));
      expect(devices.first.deviceId, 'KITEDEVICE');
      expect(devices.first.isCurrent, isTrue);
      expect(devices.first.isVerified, isTrue);
      expect(devices.first.displayName, 'Glass');
      expect(
        devices.first.lastSeenAt,
        DateTime.fromMillisecondsSinceEpoch(1758170000000, isUtc: true),
      );
      expect(devices.last.deviceId, 'PHONE');
      expect(devices.last.isCurrent, isFalse);
      expect(devices.last.isVerified, isNull);
      expect(directRoomId, '!dm:kite.test');
      expect(client.profileCalls, <(String?, String, String?)>[
        (null, 'get', null),
        ('@bob:kite.test', 'get', null),
        (null, 'search', 'bo'),
        (null, 'search_rooms', 'kite'),
        (null, 'join_room', '!public:kite.test'),
        (null, 'knock_room', '!knock:kite.test'),
        (null, 'ignored_users', null),
        (null, 'devices', null),
        ('PHONE', 'delete_device', ' secret with spaces '),
        ('@bob:kite.test', 'set_ignored', 'true'),
        (null, 'set_display_name', 'Alice Updated'),
        (null, 'set_avatar', 'mxc://kite.test/alice'),
        ('@bob:kite.test', 'open_direct', null),
      ]);
      expect(client.loginCalls, <(String, String)>[
        ('@alice:kite.test', 'test-password'),
      ]);
      expect(eventId, r'$sent');
      expect(editedEventId, r'$sent');
      expect(created.roomId, '!created:kite.test');
      expect(created.isDirect, isFalse);
      expect(roomDetails.roomId, '!room:kite.test');
      expect(roomDetails.name, 'Native room');
      expect(roomDetails.topic, 'SDK-backed settings');
      expect(roomDetails.avatarUrl, 'mxc://kite.test/avatar');
      expect(roomDetails.canonicalAlias, '#native:kite.test');
      expect(roomDetails.joinRule, 'invite');
      expect(roomDetails.encryptionEnabled, isTrue);
      expect(roomDetails.historyVisibility, 'joined');
      expect(roomDetails.notificationMode, 'allMessages');
      expect(roomDetails.isDirect, isFalse);
      expect(roomDetails.directUserIds, <String>['@bob:kite.test']);
      expect(client.createRequests.single.name, 'Kite room');
      expect(client.spaceChildWrites, <(String, String, bool)>[
        ('!space:kite.test', '!room:kite.test', true),
      ]);
      expect(client.sendCalls, <(String, String, String)>[
        ('!room:kite.test', 'kite-transaction-1', 'Hello Matrix'),
        ('!room:kite.test', 'kite-transaction-2', 'Edited Matrix'),
      ]);
      expect(client.sendReplyTargets, <String?>[r'$original', null]);
      expect(client.sendReplacementTargets, <String?>[null, r'$original']);
      expect(client.roomSettingCalls, <(String, String, String?)>[
        ('!room:kite.test', 'get', null),
        ('!room:kite.test', 'set_name', 'Renamed'),
        ('!room:kite.test', 'set_topic', null),
        ('!room:kite.test', 'set_avatar', 'mxc://kite.test/avatar'),
        ('!room:kite.test', 'set_canonical_alias', '#kite:kite.test'),
        ('!room:kite.test', 'set_join_rule', 'public'),
        ('!room:kite.test', 'enable_encryption', null),
        ('!room:kite.test', 'set_history_visibility', 'shared'),
        ('!room:kite.test', 'set_notification_mode', 'mentionsOnly'),
      ]);
      expect(client.favouriteWrites, <(String, bool)>[
        ('!room:kite.test', true),
      ]);
      expect(client.inviteResponses, <(String, bool)>[
        ('!invite:kite.test', true),
      ]);
      expect(client.memberInvites, <(String, String)>[
        ('!room:kite.test', '@bob:kite.test'),
      ]);
      expect(client.memberModerations, <(String, String, String, int, String?)>[
        ('!room:kite.test', '@bob:kite.test', 'set_power_level', 50, null),
        ('!room:kite.test', '@bob:kite.test', 'kick', 0, null),
        ('!room:kite.test', '@bob:kite.test', 'ban', 0, 'spam'),
        ('!room:kite.test', '@bob:kite.test', 'unban', 0, null),
      ]);
      expect(client.eventReports, <(String, String, String?)>[
        ('!room:kite.test', r'$abusive:kite.test', 'spam event'),
      ]);
      expect(client.eventRedactions, <(String, String, String)>[
        ('!room:kite.test', r'$sent', 'kite-redact-1'),
      ]);
      expect(client.roomManagement, <(String, String, String?, String?)>[
        ('!room:kite.test', 'report_room', null, 'spam room'),
        ('!room:kite.test', 'report_user', '@bob:kite.test', 'spam user'),
        ('!room:kite.test', 'leave', null, null),
        ('!room:kite.test', 'forget', null, null),
      ]);
      expect(client.readReceipts, <(String, String)>[
        ('!room:kite.test', r'$event'),
      ]);
    },
  );

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

  test('native bridge rejects NUL-truncated store inputs before FFI', () async {
    final bridge = MatrixRustNativeBridge(
      libraryPath: libraryPath ?? '/unused',
    );

    await expectLater(
      bridge.openEncryptedClient(
        homeserver: Uri.parse('https://matrix.example.org'),
        storePath: '/tmp/kite/alice\u0000ignored',
        storePassphrase: 'deterministic-secret',
      ),
      throwsArgumentError,
    );
    await expectLater(
      bridge.openEncryptedClient(
        homeserver: Uri.parse('https://matrix.example.org'),
        storePath: '/tmp/kite/alice',
        storePassphrase: 'secret\u0000ignored',
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
    'SDK boundary rejects NUL store secrets before opening a client',
    () async {
      final client = _FakeRustClient();
      final bridge = _RecordingRustBridge(client);
      final boundary = MatrixRustSdkBoundary(
        bridge: bridge,
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'secret\u0000truncated',
        codecExecutor: _RecordingCodecExecutor(),
      );
      addTearDown(boundary.close);

      await expectLater(
        boundary.open(
          const MatrixSdkStoreConfiguration(
            accountId: '@alice:example.org',
            storePath: '/tmp/kite/alice',
            encryptionKeyId: 'alice-key',
          ),
        ),
        throwsArgumentError,
      );
      expect(bridge.openCalls, 0);
    },
  );

  test(
    'SDK boundary refuses cross-account store replacement while open',
    () async {
      final client = _FakeRustClient();
      final bridge = _RecordingRustBridge(client);
      final boundary = MatrixRustSdkBoundary(
        bridge: bridge,
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: _RecordingCodecExecutor(),
      );
      addTearDown(boundary.close);

      const aliceStore = MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '/tmp/kite/alice',
        encryptionKeyId: 'alice-key',
      );
      const bobStore = MatrixSdkStoreConfiguration(
        accountId: '@bob:example.org',
        storePath: '/tmp/kite/bob',
        encryptionKeyId: 'bob-key',
      );

      await boundary.open(aliceStore);
      await boundary.open(aliceStore);
      expect(bridge.openCalls, 1);

      await expectLater(boundary.open(bobStore), throwsStateError);
      expect(bridge.openCalls, 1);
      expect(client.isClosed, isFalse);
    },
  );

  test('SDK boundary rejects C-incompatible sync and pagination ids', () async {
    final client = _FakeRustClient();
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
      codecExecutor: _RecordingCodecExecutor(),
    );
    addTearDown(boundary.close);

    await boundary.open(
      const MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '/tmp/kite/alice',
        encryptionKeyId: 'alice-key',
      ),
    );

    for (final cursor in <String>['', 'resume\u0000truncated']) {
      await expectLater(
        boundary.startSync(
          MatrixSdkSyncConfiguration(resumeFromCursor: cursor),
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      boundary.paginateBackwards('!room:kite.test\u0000truncated'),
      throwsArgumentError,
    );
    expect(client.syncTokens, isEmpty);
    expect(client.paginationCalls, isEmpty);
  });

  test(
    'cold initial room population yields bounded chunks before cursor commit',
    () async {
      final client = _FakeRustClient();
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: _RecordingCodecExecutor(),
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
        const MatrixSdkSyncConfiguration(
          initialRoomListLimit: 1,
          initialTimelineEventLimit: 1,
          timelineEventLimit: 20,
        ),
      );

      await client.firstSyncReturned.future;
      while (batches.where((batch) => batch.cursor == 'sync-1').length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await boundary.stopSync();

      final initial = batches
          .where((batch) => batch.cursor == 'sync-1')
          .toList(growable: false);
      expect(initial, hasLength(2));
      expect(initial.map((batch) => batch.rooms.length), <int>[1, 1]);
      expect(initial.map((batch) => batch.commitCursor), <bool>[false, true]);
      expect(
        initial.expand((batch) => batch.rooms).map((room) => room.roomId),
        <String>['!room:kite.test', '!second:kite.test'],
      );
      expect(client.syncTimelineEventLimits.first, 1);
    },
  );

  test(
    'stopping cold sync between room chunks never publishes the new cursor',
    () async {
      final client = _FakeRustClient();
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: _RecordingCodecExecutor(),
      );
      final batches = <MatrixSyncBatch>[];
      final stopped = Completer<void>();
      late final StreamSubscription<MatrixSyncBatch> subscription;
      subscription = boundary.syncBatches.listen((batch) {
        batches.add(batch);
        if (batches.length == 1 && !stopped.isCompleted) {
          boundary.stopSync().then(
            stopped.complete,
            onError: stopped.completeError,
          );
        }
      });
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
        const MatrixSdkSyncConfiguration(
          initialRoomListLimit: 1,
          initialTimelineEventLimit: 1,
          timelineEventLimit: 20,
        ),
      );
      await stopped.future;

      expect(batches, hasLength(1));
      expect(batches.single.cursor, 'sync-1');
      expect(batches.single.commitCursor, isFalse);
      expect(batches.single.rooms.single.roomId, '!room:kite.test');
      expect(client.syncTokens, <String?>[null]);
    },
  );

  test(
    'native boundary streams sync and pagination through Matrix models',
    () async {
      final client = _FakeRustClient();
      final codecExecutor = _RecordingCodecExecutor();
      final logSink = MemoryStructuredLogSink();
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: codecExecutor,
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
        const MatrixSdkSyncConfiguration(
          initialRoomListLimit: 1,
          initialTimelineEventLimit: 3,
          timelineEventLimit: 17,
          resumeFromCursor: 'resume-42',
        ),
      );

      await client.firstSyncReturned.future;
      while (client.syncTimelineEventLimits.length < 2 || batches.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await boundary.stopSync();

      expect(client.syncTimeouts.take(2), <Duration>[
        Duration.zero,
        const Duration(seconds: 1),
      ]);
      expect(client.syncTimelineEventLimits.take(2), <int>[17, 17]);
      expect(client.syncTokens.take(2), <String?>['resume-42', 'sync-1']);
      expect(batches.first.cursor, 'sync-1');
      expect(batches.first.rooms.first.summary!.displayName, 'Native room');
      expect(
        batches.first.rooms.first.timelineEvents.single.eventId,
        r'$event1',
      );

      final page = await boundary.paginateBackwards('!room:kite.test');
      expect(client.paginationCalls, <String>['!room:kite.test']);
      expect(page.roomId, '!room:kite.test');
      expect(page.reachedStart, isTrue);
      expect(page.events.single.eventId, r'$older');
      expect(batches, hasLength(1));
      expect(codecExecutor.syncDecodeCalls, greaterThanOrEqualTo(1));
      expect(codecExecutor.paginationDecodeCalls, 1);
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
      final client = _RecoveringRustClient(failuresBeforeRecovery: 6);
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
      while (batches.isEmpty || client.syncCalls < 8) {
        await Future<void>.delayed(Duration.zero);
      }
      await boundary.stopSync();

      expect(errors, hasLength(6));
      expect(errors, everyElement(isA<StateError>()));
      expect(retryDelays, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
        const Duration(seconds: 30),
      ]);
      expect(batches.first.cursor, 'recovered');
      expect(client.syncCalls, greaterThanOrEqualTo(8));
      expect(client.syncTimeouts.take(7), everyElement(Duration.zero));
      expect(client.syncTimeouts[7], const Duration(seconds: 1));
      expect(client.syncTimelineEventLimits.take(7), everyElement(8));
      expect(client.syncTimelineEventLimits[7], 20);
      final failedLogs = logSink.events
          .where(
            (event) =>
                event.flow == DiagnosticFlow.sync &&
                event.event == DiagnosticEvent.failed,
          )
          .toList(growable: false);
      expect(failedLogs, hasLength(6));
      expect(
        failedLogs.map((event) => event.metrics[DiagnosticMetric.attempt]),
        <num?>[1, 2, 3, 4, 5, 6],
      );
      expect(crashSink.reports, hasLength(6));
      expect(crashSink.reports.first.errorType, 'StateError');
      expect(crashSink.reports.first.flow, DiagnosticFlow.sync);
      expect(crashSink.reports.first.traceId, failedLogs.first.traceId);
      expect(deferredCrashReporter.release.isCompleted, isFalse);
      deferredCrashReporter.release.complete();
    },
  );

  test('native boundary maps expired SDK sessions without retrying', () async {
    final client = _SessionExpiredRustClient();
    final retryDelays = <Duration>[];
    final errors = <Object>[];
    final errorSeen = Completer<void>();
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
      syncRetryDelay: (duration) async {
        retryDelays.add(duration);
      },
    );
    final subscription = boundary.syncBatches.listen(
      (_) {},
      onError: (Object error) {
        errors.add(error);
        if (!errorSeen.isCompleted) errorSeen.complete();
      },
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
    await errorSeen.future;
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<MatrixNonRetryableSyncException>());
    expect(
      (errors.single as MatrixNonRetryableSyncException).cause,
      isA<MatrixSessionExpiredException>(),
    );
    expect(client.syncCalls, 1);
    expect(retryDelays, isEmpty);
  });

  test(
    'malformed decoded sync stops instead of retrying the same payload forever',
    () async {
      final client = _FakeRustClient();
      final retryDelays = <Duration>[];
      final errors = <Object>[];
      final boundary = MatrixRustSdkBoundary(
        bridge: _FakeRustBridge(client),
        homeserver: Uri.parse('https://matrix.example.org'),
        resolveStoreSecret: (_) async => 'deterministic-secret',
        codecExecutor: const _MalformedSyncCodecExecutor(),
        syncRetryDelay: (duration) async {
          retryDelays.add(duration);
        },
      );
      final errorSeen = Completer<void>();
      final subscription = boundary.syncBatches.listen(
        (_) {},
        onError: (Object error) {
          errors.add(error);
          if (!errorSeen.isCompleted) errorSeen.complete();
        },
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
      await errorSeen.future;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<MatrixNonRetryableSyncException>());
      expect(
        (errors.single as MatrixNonRetryableSyncException).cause,
        isA<FormatException>(),
      );
      expect(client.syncTokens, <String?>[null]);
      expect(retryDelays, isEmpty);
    },
  );

  test('stopping sync interrupts a pending retry backoff', () async {
    final client = _RecoveringRustClient(failuresBeforeRecovery: 100);
    final retryStarted = Completer<Duration>();
    final blockedDelay = Completer<void>();
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
      syncRetryDelay: (duration) {
        if (!retryStarted.isCompleted) retryStarted.complete(duration);
        return blockedDelay.future;
      },
    );
    final subscription = boundary.syncBatches.listen(
      (_) {},
      onError: (Object _) {},
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

    expect(await retryStarted.future, const Duration(seconds: 1));
    await boundary.stopSync().timeout(const Duration(seconds: 1));

    expect(blockedDelay.isCompleted, isFalse);
    expect(client.syncCalls, 1);
    blockedDelay.complete();
  });

  test('failed SDK client close remains retryable', () async {
    final client = _FailingCloseRustClient();
    final boundary = MatrixRustSdkBoundary(
      bridge: _FakeRustBridge(client),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'deterministic-secret',
    );

    await boundary.open(
      const MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '/tmp/kite/alice',
        encryptionKeyId: 'alice-key',
      ),
    );

    await expectLater(boundary.close(), throwsStateError);
    expect(client.closeCalls, 1);
    expect(client.isClosed, isFalse);

    await boundary.close();
    expect(client.closeCalls, 2);
    expect(client.isClosed, isTrue);
  });

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

  test(
    'native login keeps homeserver failures distinct from rejected credentials',
    () async {
      await _expectNativeLoginFailure(
        libraryPath: libraryPath!,
        statusCode: HttpStatus.internalServerError,
        errcode: 'M_UNKNOWN',
        expectedCode: 'login_failed',
      );
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );

  test(
    'native login preserves Matrix forbidden as credential rejection',
    () async {
      await _expectNativeLoginFailure(
        libraryPath: libraryPath!,
        statusCode: HttpStatus.forbidden,
        errcode: 'M_FORBIDDEN',
        expectedCode: 'authentication_rejected',
      );
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );
}

Future<void> _expectNativeLoginFailure({
  required String libraryPath,
  required int statusCode,
  required String errcode,
  required String expectedCode,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (request.method == 'GET' && path == '/_matrix/client/versions') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(
        '{"versions":["v1.1","v1.11"],"unstable_features":{}}',
      );
    } else if (request.method == 'GET' && path == '/_matrix/client/v3/login') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('{"flows":[{"type":"m.login.password"}]}');
    } else if (request.method == 'POST' && path == '/_matrix/client/v3/login') {
      await request.drain<void>();
      request.response.statusCode = statusCode;
      request.response.write(
        '{"errcode":"$errcode","error":"Controlled login failure"}',
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('{"errcode":"M_NOT_FOUND","error":"Not found"}');
    }
    await request.response.close();
  });

  final temp = await Directory.systemTemp.createTemp(
    'kite-native-login-failure-',
  );
  MatrixRustNativeClient? client;
  try {
    final bridge = MatrixRustNativeBridge(libraryPath: libraryPath);
    final homeserver = Uri.parse('http://127.0.0.1:${server.port}');
    final discovery = await bridge.discoverAuthentication(homeserver);
    expect(discovery.passwordAvailable, isTrue);

    client = await bridge.openEncryptedClient(
      homeserver: homeserver,
      storePath: temp.path,
      storePassphrase: 'deterministic-login-failure-secret',
    );

    await expectLater(
      client.loginWithPassword(
        username: 'probe-user',
        password: 'probe-password',
      ),
      throwsA(
        isA<MatrixRustNativeException>().having(
          (error) => error.code,
          'code',
          expectedCode,
        ),
      ),
    );
  } finally {
    await client?.close();
    await server.close(force: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  }
}

final class _RecordingCodecExecutor implements MatrixRustCodecExecutor {
  final MatrixRustSyncCodec _codec = MatrixRustSyncCodec();
  int syncDecodeCalls = 0;
  int paginationDecodeCalls = 0;

  @override
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload) async {
    syncDecodeCalls += 1;
    return _codec.decodeSync(payload);
  }

  @override
  Future<MatrixRustPaginationDecodeResult> decodePagination(
    String payload,
  ) async {
    paginationDecodeCalls += 1;
    return _codec.decodePagination(payload);
  }
}

final class _MalformedSyncCodecExecutor implements MatrixRustCodecExecutor {
  const _MalformedSyncCodecExecutor();

  @override
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload) {
    throw const FormatException('deterministic malformed sync payload');
  }

  @override
  Future<MatrixRustPaginationDecodeResult> decodePagination(String payload) {
    throw UnimplementedError();
  }
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

final class _RecordingRustBridge implements MatrixRustBridge {
  _RecordingRustBridge(this.client);

  final MatrixRustClient client;
  int openCalls = 0;

  @override
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  }) async {
    openCalls += 1;
    return client;
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

final class _FailingCloseRustClient implements MatrixRustClient {
  int closeCalls = 0;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closeCalls == 1) {
      throw StateError('deterministic close failure');
    }
    _closed = true;
  }
}

final class _SessionExpiredRustClient implements MatrixRustClient {
  int syncCalls = 0;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) async {
    syncCalls += 1;
    return '{"error":{"code":"unknown_token"}}';
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

final class _RecoveringRustClient implements MatrixRustClient {
  _RecoveringRustClient({this.failuresBeforeRecovery = 1});

  final int failuresBeforeRecovery;
  final Completer<void> recovered = Completer<void>();
  final List<Duration> syncTimeouts = <Duration>[];
  final List<int> syncTimelineEventLimits = <int>[];
  int syncCalls = 0;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) async {
    syncTimeouts.add(timeout);
    syncTimelineEventLimits.add(timelineEventLimit);
    syncCalls += 1;
    if (syncCalls <= failuresBeforeRecovery) {
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

final class _FakeRustClient
    implements
        MatrixRustClient,
        MatrixRustRoomCreator,
        MatrixRustSpaceClient,
        MatrixRustRoomFavouriteClient,
        MatrixRustRoomInviteClient,
        MatrixRustRoomMemberInviterClient,
        MatrixRustRoomMemberModeratorClient,
        MatrixRustRoomLifecycleClient,
        MatrixRustTimelineModerationClient,
        MatrixRustTimelineRedactionClient,
        MatrixRustRoomSettingsClient,
        MatrixRustMediaPrefetchClient,
        MatrixRustMediaClient,
        MatrixRustProfileClient,
        MatrixRustEncryptionRecoveryClient,
        MatrixRustRoomReadClient {
  final Completer<void> firstSyncReturned = Completer<void>();
  final List<Duration> syncTimeouts = <Duration>[];
  final List<int> syncTimelineEventLimits = <int>[];
  final List<String?> syncTokens = <String?>[];
  final List<String> paginationCalls = <String>[];
  final List<(String, String, String)> sendCalls = <(String, String, String)>[];
  final List<String?> sendReplyTargets = <String?>[];
  final List<String?> sendReplacementTargets = <String?>[];
  final List<(String, String)> loginCalls = <(String, String)>[];
  final List<MatrixSdkRoomCreationRequest> createRequests =
      <MatrixSdkRoomCreationRequest>[];
  final List<(String, String, bool)> spaceChildWrites =
      <(String, String, bool)>[];
  final List<(String, bool)> favouriteWrites = <(String, bool)>[];
  final List<(String, bool)> inviteResponses = <(String, bool)>[];
  final List<(String, String)> memberInvites = <(String, String)>[];
  final List<(String, String, String, int, String?)> memberModerations =
      <(String, String, String, int, String?)>[];
  final List<(String, String, String?, String?)> roomManagement =
      <(String, String, String?, String?)>[];
  final List<(String, String, String?)> eventReports =
      <(String, String, String?)>[];
  final List<(String, String, String)> eventRedactions =
      <(String, String, String)>[];
  final List<(String, String, String?)> roomSettingCalls =
      <(String, String, String?)>[];
  final List<(String?, String, String?)> profileCalls =
      <(String?, String, String?)>[];
  final List<(String, List<int>)> mediaUploads = <(String, List<int>)>[];
  final List<(String, int, int)> mediaDownloads = <(String, int, int)>[];
  final List<(String, String)> readReceipts = <(String, String)>[];
  final List<String> operationOrder = <String>[];
  final List<int> prefetchBatchSizes = <int>[];
  Completer<void>? prefetchGate;
  final Completer<void> prefetchStarted = Completer<void>();
  int _prefetchCalls = 0;

  bool _closed = false;
  int _syncCalls = 0;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginCalls.add((username, password));
    return const MatrixRustLoginResult(
      userId: '@alice:kite.test',
      deviceId: 'KITEDEVICE',
    );
  }

  @override
  Future<MatrixRustCreatedRoom> createRoom(
    MatrixSdkRoomCreationRequest request,
  ) async {
    createRequests.add(request);
    return const MatrixRustCreatedRoom(
      roomId: '!created:kite.test',
      isDirect: false,
    );
  }

  @override
  Future<void> setSpaceChild({
    required String spaceId,
    required String roomId,
    required bool linked,
  }) async {
    spaceChildWrites.add((spaceId, roomId, linked));
  }

  @override
  Future<void> setRoomFavourite({
    required String roomId,
    required bool isFavourite,
  }) async {
    favouriteWrites.add((roomId, isFavourite));
  }

  @override
  Future<void> respondToInvite({
    required String roomId,
    required bool accept,
  }) async {
    inviteResponses.add((roomId, accept));
  }

  @override
  Future<void> inviteRoomMember({
    required String roomId,
    required String userId,
  }) async {
    memberInvites.add((roomId, userId));
  }

  @override
  Future<MatrixRustRoomMemberPermissions> roomMemberPermissions({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
  }) async {
    return const MatrixRustRoomMemberPermissions(
      actorPowerLevel: 50,
      canInvite: true,
      canChangePowerLevel: true,
      canKick: true,
      canBan: true,
      canUnban: true,
    );
  }

  @override
  Future<void> moderateRoomMember({
    required String roomId,
    required String userId,
    required String action,
    int powerLevel = 0,
    String? reason,
  }) async {
    memberModerations.add((roomId, userId, action, powerLevel, reason));
  }

  @override
  Future<void> manageRoom({
    required String roomId,
    required String action,
    String? userId,
    String? reason,
  }) async {
    roomManagement.add((roomId, action, userId, reason));
  }

  @override
  Future<void> reportContent({
    required String roomId,
    required String eventId,
    String? reason,
  }) async {
    eventReports.add((roomId, eventId, reason));
  }

  @override
  Future<void> redactEvent({
    required String roomId,
    required String eventId,
    required String transactionId,
  }) async {
    eventRedactions.add((roomId, eventId, transactionId));
  }

  @override
  Future<Map<String, Object?>> roomSettings({
    required String roomId,
    required String action,
    String? value,
  }) async {
    roomSettingCalls.add((roomId, action, value));
    if (action == 'get_encryption_trust') {
      return <String, Object?>{
        'roomId': roomId,
        'isEncrypted': true,
        'allDevicesVerified': true,
      };
    }
    if (action == 'get') {
      return <String, Object?>{
        'roomId': roomId,
        'name': 'Native room',
        'topic': 'SDK-backed settings',
        'avatarUrl': 'mxc://kite.test/avatar',
        'canonicalAlias': '#native:kite.test',
        'joinRule': 'invite',
        'encryptionEnabled': true,
        'historyVisibility': 'joined',
        'notificationMode': 'allMessages',
        'isDirect': false,
        'directUserIds': <String>['@bob:kite.test'],
      };
    }
    return <String, Object?>{'roomId': roomId, 'action': action};
  }

  @override
  Future<Map<String, Uint8List>> prefetchMedia({
    required List<String> contentUris,
    Map<String, Map<String, Object?>> encryptedFiles =
        const <String, Map<String, Object?>>{},
    required int width,
    required int height,
  }) async {
    _prefetchCalls += 1;
    prefetchBatchSizes.add(contentUris.length);
    operationOrder.add('prefetch-$_prefetchCalls');
    if (_prefetchCalls == 1 && prefetchGate != null) {
      if (!prefetchStarted.isCompleted) prefetchStarted.complete();
      await prefetchGate!.future;
    }
    return <String, Uint8List>{
      for (final uri in contentUris) uri: Uint8List.fromList(<int>[1]),
    };
  }

  Map<String, Object?> _recoveryStatusData() => <String, Object?>{
    'recoveryState': 'enabled',
    'backupState': 'enabled',
    'backupExistsOnServer': true,
  };

  @override
  Future<Map<String, Object?>> encryptionRecoveryStatus() async {
    operationOrder.add('recovery-status');
    return _recoveryStatusData();
  }

  @override
  Future<Map<String, Object?>> createEncryptedBackup() async =>
      _recoveryStatusData();

  @override
  Future<Map<String, Object?>> recoverEncryption(String secret) async =>
      _recoveryStatusData();

  @override
  Future<Map<String, Object?>> recoverEncryptedHistory() async =>
      _recoveryStatusData();

  @override
  Future<Map<String, Object?>> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) async => <String, Object?>{
    ..._recoveryStatusData(),
    'importedCount': 1,
    'totalCount': 1,
  };

  @override
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  }) async {
    mediaUploads.add((mimeType, List<int>.from(bytes)));
    return 'mxc://kite.test/uploaded-media';
  }

  @override
  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) async {
    operationOrder.add('download-media');
    mediaDownloads.add((contentUri, width, height));
    return Uint8List.fromList(<int>[4, 3, 2, 1]);
  }

  @override
  Future<Map<String, Object?>> profile({
    String? userId,
    required String action,
    String? value,
  }) async {
    profileCalls.add((userId, action, value));
    if (action == 'cross_signing_trust') {
      return <String, Object?>{'trust': 'verified'};
    }
    if (action == 'get') {
      return <String, Object?>{
        'userId': userId ?? '@alice:kite.test',
        'displayName': userId == null ? 'Alice' : 'Bob',
        'avatarUrl': userId == null ? 'mxc://kite.test/alice-old' : null,
      };
    }
    if (action == 'search') {
      return <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'userId': '@bob:kite.test',
            'displayName': 'Bob',
            'avatarUrl': 'mxc://kite.test/bob',
          },
        ],
      };
    }
    if (action == 'search_rooms') {
      return <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'roomId': '!public:kite.test',
            'name': 'Kite Community',
            'topic': 'Public Matrix room',
            'canonicalAlias': '#kite:kite.test',
            'avatarUrl': 'mxc://kite.test/public',
            'joinRule': 'public',
            'worldReadable': true,
            'joinedMembers': 42,
          },
        ],
      };
    }
    if (action == 'join_room') {
      return <String, Object?>{'roomId': value, 'membership': 'joined'};
    }
    if (action == 'knock_room') {
      return <String, Object?>{'roomId': value, 'membership': 'knocked'};
    }
    if (action == 'ignored_users') {
      return <String, Object?>{
        'userIds': <Object?>['@spam:kite.test'],
      };
    }
    if (action == 'devices') {
      return <String, Object?>{
        'devices': <Object?>[
          <String, Object?>{
            'deviceId': 'KITEDEVICE',
            'displayName': 'Glass',
            'lastSeenAtMs': 1758170000000,
            'isCurrent': true,
            'verification': 'verified',
          },
          <String, Object?>{
            'deviceId': 'PHONE',
            'displayName': 'Phone',
            'lastSeenAtMs': null,
            'isCurrent': false,
            'verification': 'unknown',
          },
        ],
      };
    }
    if (action == 'delete_device') {
      return <String, Object?>{'action': action, 'deviceId': userId};
    }
    if (action == 'set_ignored') {
      return <String, Object?>{
        'action': action,
        'userId': userId,
        'ignored': value == 'true',
      };
    }
    if (action == 'open_direct') {
      return <String, Object?>{'roomId': '!dm:kite.test'};
    }
    return <String, Object?>{'action': action};
  }

  @override
  Future<void> markRoomRead({
    required String roomId,
    required String eventId,
  }) async {
    readReceipts.add((roomId, eventId));
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) async {
    sendCalls.add((roomId, transactionId, body));
    sendReplyTargets.add(replyToEventId);
    sendReplacementTargets.add(replacementEventId);
    return const MatrixRustSendResult(eventId: r'$sent');
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) async {
    syncTimeouts.add(timeout);
    syncTimelineEventLimits.add(timelineEventLimit);
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
            },
            {
              "roomId": "!second:kite.test",
              "displayName": "Second room",
              "unreadCount": 0,
              "prevBatch": "back-2",
              "events": []
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
