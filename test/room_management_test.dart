import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

void main() {
  test('DM creation enforces encrypted invite-only direct semantics', () async {
    final fixture = _fixture(seed: 10);

    final room = await fixture.coordinator.createDirectMessage(
      '  @alice:example.org  ',
    );

    expect(room.roomId, '!room11:example.org');
    expect(room.isDirect, isTrue);
    final create = fixture.rooms.invocations.single;
    expect(create.type, RoomManagementInvocationType.create);
    expect(create.creation?.kind, KiteRoomCreationKind.directMessage);
    expect(create.creation?.invitees, <String>['@alice:example.org']);
    expect(create.creation?.joinRule, KiteRoomJoinRule.invite);
    expect(create.creation?.encryptionEnabled, isTrue);
    expect(
      create.creation?.historyVisibility,
      KiteRoomHistoryVisibility.joined,
    );
    expect(fixture.directMetadata.invocations, hasLength(1));
    expect(fixture.directMetadata.invocations.single.userIds, <String>{
      '@alice:example.org',
    });
  });

  test('invalid DM user IDs never touch the Matrix room boundary', () async {
    final fixture = _fixture();

    await expectLater(
      fixture.coordinator.createDirectMessage('alice'),
      throwsA(isA<RoomManagementValidationException>()),
    );

    expect(fixture.rooms.invocations, isEmpty);
    expect(fixture.directMetadata.invocations, isEmpty);
  });

  test('private room uses safe defaults and normalises inputs', () async {
    final fixture = _fixture();

    await fixture.coordinator.createPrivateRoom(
      name: '  Project Kite  ',
      topic: '  Stable chat  ',
      invitees: const <String>[
        ' @alice:example.org ',
        '@bob:example.org',
        '@alice:example.org',
      ],
      parentSpaceId: ' !space:example.org ',
    );

    final request = fixture.rooms.invocations.last.creation!;
    expect(request.kind, KiteRoomCreationKind.privateRoom);
    expect(request.name, 'Project Kite');
    expect(request.topic, 'Stable chat');
    expect(request.invitees, <String>[
      '@alice:example.org',
      '@bob:example.org',
    ]);
    expect(request.joinRule, KiteRoomJoinRule.invite);
    expect(request.encryptionEnabled, isTrue);
    expect(request.historyVisibility, KiteRoomHistoryVisibility.joined);
    expect(request.parentSpaceId, '!space:example.org');
  });

  test(
    'knock and restricted private rooms require homeserver support',
    () async {
      final fixture = _fixture(
        capabilities: KiteRoomCapabilities(
          canCreatePublicRooms: true,
          supportedJoinRules: const <KiteRoomJoinRule>{
            KiteRoomJoinRule.invite,
            KiteRoomJoinRule.knock,
          },
        ),
      );

      await fixture.coordinator.createPrivateRoom(
        name: 'Knock room',
        joinRule: KiteRoomJoinRule.knock,
      );
      await expectLater(
        fixture.coordinator.createPrivateRoom(
          name: 'Restricted room',
          joinRule: KiteRoomJoinRule.restricted,
        ),
        throwsA(isA<RoomManagementValidationException>()),
      );

      expect(
        fixture.rooms.invocations.where(
          (entry) => entry.type == RoomManagementInvocationType.create,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'public room creation obeys server policy and validates aliases',
    () async {
      final fixture = _fixture();

      await fixture.coordinator.createPublicRoom(
        name: 'Community',
        canonicalAlias: ' #community:example.org ',
      );

      final request = fixture.rooms.invocations.last.creation!;
      expect(request.kind, KiteRoomCreationKind.publicRoom);
      expect(request.joinRule, KiteRoomJoinRule.public);
      expect(request.canonicalAlias, '#community:example.org');
      expect(request.encryptionEnabled, isFalse);
      expect(request.historyVisibility, KiteRoomHistoryVisibility.shared);

      await expectLater(
        fixture.coordinator.createPublicRoom(
          name: 'Bad alias',
          canonicalAlias: 'not-an-alias',
        ),
        throwsA(isA<RoomManagementValidationException>()),
      );

      fixture.rooms.roomCapabilities = KiteRoomCapabilities(
        canCreatePublicRooms: false,
        supportedJoinRules: const <KiteRoomJoinRule>{KiteRoomJoinRule.invite},
      );
      await expectLater(
        fixture.coordinator.createPublicRoom(name: 'Blocked'),
        throwsA(isA<RoomManagementValidationException>()),
      );
    },
  );

  test(
    'room metadata mutations preserve Matrix identifiers and safe media URIs',
    () async {
      final fixture = _fixture();
      const roomId = '!room:example.org';

      await fixture.coordinator.setName(roomId: roomId, name: '  New name  ');
      await fixture.coordinator.setTopic(roomId: roomId, topic: '   ');
      await fixture.coordinator.setAvatar(
        roomId: roomId,
        avatarUrl: Uri.parse('mxc://example.org/avatar'),
      );
      await fixture.coordinator.setCanonicalAlias(
        roomId: roomId,
        canonicalAlias: '#kite:example.org',
      );
      await fixture.coordinator.setJoinRule(
        roomId: roomId,
        joinRule: KiteRoomJoinRule.restricted,
      );
      await fixture.coordinator.enableEncryption(roomId);
      await fixture.coordinator.setHistoryVisibility(
        roomId: roomId,
        visibility: KiteRoomHistoryVisibility.invited,
      );
      await fixture.coordinator.setNotificationMode(
        roomId: roomId,
        mode: KiteRoomNotificationMode.mentionsOnly,
      );

      final mutations = fixture.rooms.invocations
          .where(
            (entry) => entry.type != RoomManagementInvocationType.capabilities,
          )
          .toList(growable: false);
      expect(
        mutations.map((entry) => entry.type),
        <RoomManagementInvocationType>[
          RoomManagementInvocationType.setName,
          RoomManagementInvocationType.setTopic,
          RoomManagementInvocationType.setAvatar,
          RoomManagementInvocationType.setCanonicalAlias,
          RoomManagementInvocationType.setJoinRule,
          RoomManagementInvocationType.enableEncryption,
          RoomManagementInvocationType.setHistoryVisibility,
          RoomManagementInvocationType.setNotificationMode,
        ],
      );
      expect(mutations[0].text, 'New name');
      expect(mutations[1].text, isNull);
      expect(mutations[2].avatarUrl.toString(), 'mxc://example.org/avatar');

      expect(
        () => fixture.coordinator.setAvatar(
          roomId: roomId,
          avatarUrl: Uri.parse('https://example.org/avatar.jpg'),
        ),
        throwsA(isA<RoomManagementValidationException>()),
      );
    },
  );

  test('encryption is one-way at the coordinator boundary', () async {
    final fixture = _fixture();

    await fixture.coordinator.enableEncryption('!room:example.org');

    expect(
      fixture.rooms.invocations.single.type,
      RoomManagementInvocationType.enableEncryption,
    );
  });

  test('reading SDK room details reconciles current direct-message metadata automatically', () async {
    final fixture = _fixture();
    fixture.rooms.detailsByRoomId['!dm:example.org'] = KiteRoomDetails(
      roomId: '!dm:example.org',
      name: null,
      topic: null,
      avatarUrl: null,
      canonicalAlias: null,
      joinRule: KiteRoomJoinRule.invite,
      encryptionEnabled: true,
      historyVisibility: KiteRoomHistoryVisibility.joined,
      notificationMode: KiteRoomNotificationMode.allMessages,
      isDirect: true,
      directUserIds: const <String>{'@alice:example.org'},
    );

    final direct = await fixture.coordinator.roomDetails('!dm:example.org');
    expect(direct.isDirect, isTrue);
    expect(fixture.directMetadata.invocations.single.userIds, <String>{
      '@alice:example.org',
    });

    fixture.rooms.detailsByRoomId['!dm:example.org'] = KiteRoomDetails(
      roomId: '!dm:example.org',
      name: 'Now a room',
      topic: null,
      avatarUrl: null,
      canonicalAlias: null,
      joinRule: KiteRoomJoinRule.invite,
      encryptionEnabled: true,
      historyVisibility: KiteRoomHistoryVisibility.joined,
      notificationMode: KiteRoomNotificationMode.allMessages,
      isDirect: false,
      directUserIds: const <String>{},
    );

    final room = await fixture.coordinator.roomDetails('!dm:example.org');
    expect(room.isDirect, isFalse);
    expect(fixture.directMetadata.invocations.last.userIds, isEmpty);
  });

  test(
    'SDK room metadata reconciles DM mappings when semantics change',
    () async {
      final fixture = _fixture();

      await fixture.coordinator.reconcileDirectMetadata(
        KiteRoomDetails(
          roomId: '!dm:example.org',
          name: null,
          topic: null,
          avatarUrl: null,
          canonicalAlias: null,
          joinRule: KiteRoomJoinRule.invite,
          encryptionEnabled: true,
          historyVisibility: KiteRoomHistoryVisibility.joined,
          notificationMode: KiteRoomNotificationMode.allMessages,
          isDirect: true,
          directUserIds: const <String>{'@alice:example.org'},
        ),
      );
      await fixture.coordinator.reconcileDirectMetadata(
        KiteRoomDetails(
          roomId: '!dm:example.org',
          name: 'Now a room',
          topic: null,
          avatarUrl: null,
          canonicalAlias: null,
          joinRule: KiteRoomJoinRule.invite,
          encryptionEnabled: true,
          historyVisibility: KiteRoomHistoryVisibility.joined,
          notificationMode: KiteRoomNotificationMode.allMessages,
          isDirect: false,
          directUserIds: const <String>{},
        ),
      );

      expect(fixture.directMetadata.invocations, hasLength(2));
      expect(fixture.directMetadata.invocations.first.userIds, <String>{
        '@alice:example.org',
      });
      expect(fixture.directMetadata.invocations.last.userIds, isEmpty);
    },
  );

  test(
    'room and user reports preserve Matrix identity and optional reasons',
    () async {
      final fixture = _fixture();

      await fixture.coordinator.reportRoom(
        roomId: ' !room:example.org ',
        reason: '  abusive room  ',
      );
      await fixture.coordinator.reportUser(
        roomId: '!room:example.org',
        userId: ' @alice:example.org ',
        reason: '   ',
      );
      await fixture.coordinator.reportRoom(roomId: '!room:example.org');

      expect(
        fixture.rooms.invocations.map((entry) => entry.type),
        <RoomManagementInvocationType>[
          RoomManagementInvocationType.reportRoom,
          RoomManagementInvocationType.reportUser,
          RoomManagementInvocationType.reportRoom,
        ],
      );
      expect(fixture.rooms.invocations[0].roomId, '!room:example.org');
      expect(fixture.rooms.invocations[0].reason, 'abusive room');
      expect(fixture.rooms.invocations[1].userId, '@alice:example.org');
      expect(fixture.rooms.invocations[1].reason, isNull);
      expect(fixture.rooms.invocations[2].reason, isNull);
    },
  );

  test(
    'leave and forget clear stale direct-room metadata only after SDK success',
    () async {
      final fixture = _fixture();

      await fixture.coordinator.leaveRoom(' !dm:example.org ');
      await fixture.coordinator.forgetRoom('!dm:example.org');

      expect(
        fixture.rooms.invocations.map((entry) => entry.type),
        <RoomManagementInvocationType>[
          RoomManagementInvocationType.leaveRoom,
          RoomManagementInvocationType.forgetRoom,
        ],
      );
      expect(fixture.directMetadata.invocations, hasLength(2));
      expect(
        fixture.directMetadata.invocations.first.roomId,
        '!dm:example.org',
      );
      expect(fixture.directMetadata.invocations.first.userIds, isEmpty);
      expect(fixture.directMetadata.invocations.last.userIds, isEmpty);

      final failed = _fixture();
      failed.rooms.failNextWith = StateError('leave failed');
      await expectLater(
        failed.coordinator.leaveRoom('!dm:example.org'),
        throwsStateError,
      );
      expect(failed.directMetadata.invocations, isEmpty);
    },
  );

  test('boundary failures never mutate direct metadata prematurely', () async {
    final fixture = _fixture();
    fixture.rooms.failNextWith = StateError('server failed');

    await expectLater(
      fixture.coordinator.createDirectMessage('@alice:example.org'),
      throwsStateError,
    );

    expect(fixture.directMetadata.invocations, isEmpty);
  });
}

_RoomFixture _fixture({int seed = 0, KiteRoomCapabilities? capabilities}) {
  final rooms = DeterministicRoomManagementPort(
    seed: seed,
    roomCapabilities: capabilities,
  );
  final directMetadata = DeterministicDirectRoomMetadataPort();
  return _RoomFixture(
    rooms: rooms,
    directMetadata: directMetadata,
    coordinator: RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: directMetadata,
    ),
  );
}

final class _RoomFixture {
  const _RoomFixture({
    required this.rooms,
    required this.directMetadata,
    required this.coordinator,
  });

  final DeterministicRoomManagementPort rooms;
  final DeterministicDirectRoomMetadataPort directMetadata;
  final RoomManagementCoordinator coordinator;
}
