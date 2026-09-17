import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/matrix_room_creation_adapter.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  test(
    'production room creation adapter preserves Matrix room semantics',
    () async {
      MatrixSdkRoomCreationRequest? captured;
      final port = MatrixRoomCreationManagementPort(
        (request) async {
          captured = request;
          return const MatrixSdkCreatedRoom(
            roomId: '!created:example.org',
            isDirect: false,
          );
        },
        reportRoom: (_, _) async {},
        reportUser: (_, _, _) async {},
        leaveRoom: (_) async {},
        forgetRoom: (_) async {},
        roomDetails: _details,
        setName: (_, _) async {},
        setTopic: (_, _) async {},
        setAvatar: (_, _) async {},
        setCanonicalAlias: (_, _) async {},
        setJoinRule: (_, _) async {},
        enableEncryption: (_) async {},
        setHistoryVisibility: (_, _) async {},
        setNotificationMode: (_, _) async {},
      );

      final created = await port.createRoom(
        KiteRoomCreationRequest(
          kind: KiteRoomCreationKind.privateRoom,
          name: 'Project',
          topic: 'Planning',
          invitees: const <String>['@alice:example.org'],
          joinRule: KiteRoomJoinRule.invite,
          encryptionEnabled: true,
          historyVisibility: KiteRoomHistoryVisibility.joined,
          canonicalAlias: null,
          parentSpaceId: null,
        ),
      );

      expect(created.roomId, '!created:example.org');
      expect(captured?.kind, MatrixSdkRoomCreationKind.privateRoom);
      expect(captured?.name, 'Project');
      expect(captured?.invitees, const <String>['@alice:example.org']);
      expect(captured?.joinRule, 'invite');
      expect(captured?.encryptionEnabled, isTrue);
      expect(captured?.historyVisibility, 'joined');
    },
  );

  test(
    'production creation capabilities expose only implemented join rules',
    () async {
      final port = MatrixRoomCreationManagementPort(
        (_) async => const MatrixSdkCreatedRoom(
          roomId: '!unused:example.org',
          isDirect: false,
        ),
        reportRoom: (_, _) async {},
        reportUser: (_, _, _) async {},
        leaveRoom: (_) async {},
        forgetRoom: (_) async {},
        roomDetails: _details,
        setName: (_, _) async {},
        setTopic: (_, _) async {},
        setAvatar: (_, _) async {},
        setCanonicalAlias: (_, _) async {},
        setJoinRule: (_, _) async {},
        enableEncryption: (_) async {},
        setHistoryVisibility: (_, _) async {},
        setNotificationMode: (_, _) async {},
      );

      final capabilities = await port.capabilities();

      expect(capabilities.canCreatePublicRooms, isTrue);
      expect(capabilities.supportedJoinRules, <KiteRoomJoinRule>{
        KiteRoomJoinRule.invite,
        KiteRoomJoinRule.public,
      });
    },
  );

  test(
    'production room lifecycle mutations route exact Matrix identities',
    () async {
      final invocations = <String>[];
      final port = MatrixRoomCreationManagementPort(
        (_) async => const MatrixSdkCreatedRoom(
          roomId: '!unused:example.org',
          isDirect: false,
        ),
        reportRoom: (roomId, reason) async =>
            invocations.add('report-room:$roomId:$reason'),
        reportUser: (roomId, userId, reason) async =>
            invocations.add('report-user:$roomId:$userId:$reason'),
        leaveRoom: (roomId) async => invocations.add('leave:$roomId'),
        forgetRoom: (roomId) async => invocations.add('forget:$roomId'),
        roomDetails: _details,
        setName: (_, _) async {},
        setTopic: (_, _) async {},
        setAvatar: (_, _) async {},
        setCanonicalAlias: (_, _) async {},
        setJoinRule: (_, _) async {},
        enableEncryption: (_) async {},
        setHistoryVisibility: (_, _) async {},
        setNotificationMode: (_, _) async {},
      );

      await port.reportRoom(roomId: '!room:example.org', reason: 'spam');
      await port.reportUser(
        roomId: '!room:example.org',
        userId: '@bob:example.org',
        reason: 'abuse',
      );
      await port.leaveRoom('!room:example.org');
      await port.forgetRoom('!room:example.org');

      expect(invocations, <String>[
        'report-room:!room:example.org:spam',
        'report-user:!room:example.org:@bob:example.org:abuse',
        'leave:!room:example.org',
        'forget:!room:example.org',
      ]);
    },
  );

  test('production room settings adapter preserves SDK-backed values and mutations', () async {
    final invocations = <String>[];
    final port = MatrixRoomCreationManagementPort(
      (_) async => const MatrixSdkCreatedRoom(
        roomId: '!unused:example.org',
        isDirect: false,
      ),
      reportRoom: (_, _) async {},
      reportUser: (_, _, _) async {},
      leaveRoom: (_) async {},
      forgetRoom: (_) async {},
      roomDetails: _details,
      setName: (roomId, value) async => invocations.add('name:$roomId:$value'),
      setTopic: (roomId, value) async =>
          invocations.add('topic:$roomId:$value'),
      setAvatar: (roomId, value) async =>
          invocations.add('avatar:$roomId:$value'),
      setCanonicalAlias: (roomId, value) async =>
          invocations.add('alias:$roomId:$value'),
      setJoinRule: (roomId, value) async =>
          invocations.add('join:$roomId:$value'),
      enableEncryption: (roomId) async => invocations.add('encrypt:$roomId'),
      setHistoryVisibility: (roomId, value) async =>
          invocations.add('history:$roomId:$value'),
      setNotificationMode: (roomId, value) async =>
          invocations.add('notifications:$roomId:$value'),
    );

    final details = await port.roomDetails('!room:example.org');
    await port.setName(roomId: details.roomId, name: 'Renamed');
    await port.setTopic(roomId: details.roomId, topic: null);
    await port.setAvatar(
      roomId: details.roomId,
      avatarUrl: Uri.parse('mxc://example.org/new-avatar'),
    );
    await port.setCanonicalAlias(
      roomId: details.roomId,
      canonicalAlias: '#renamed:example.org',
    );
    await port.setJoinRule(
      roomId: details.roomId,
      joinRule: KiteRoomJoinRule.public,
    );
    await port.enableEncryption(details.roomId);
    await port.setHistoryVisibility(
      roomId: details.roomId,
      visibility: KiteRoomHistoryVisibility.shared,
    );
    await port.setNotificationMode(
      roomId: details.roomId,
      mode: KiteRoomNotificationMode.mentionsOnly,
    );

    expect(details.name, 'Native room');
    expect(details.topic, 'SDK-backed settings');
    expect(details.avatarUrl, Uri.parse('mxc://example.org/avatar'));
    expect(details.canonicalAlias, '#native:example.org');
    expect(details.joinRule, KiteRoomJoinRule.invite);
    expect(details.encryptionEnabled, isTrue);
    expect(details.historyVisibility, KiteRoomHistoryVisibility.joined);
    expect(details.notificationMode, KiteRoomNotificationMode.allMessages);
    expect(details.isDirect, isFalse);
    expect(details.directUserIds, <String>{'@bob:example.org'});
    expect(invocations, <String>[
      'name:!room:example.org:Renamed',
      'topic:!room:example.org:null',
      'avatar:!room:example.org:mxc://example.org/new-avatar',
      'alias:!room:example.org:#renamed:example.org',
      'join:!room:example.org:public',
      'encrypt:!room:example.org',
      'history:!room:example.org:shared',
      'notifications:!room:example.org:mentionsOnly',
    ]);
  });
}

Future<MatrixSdkRoomDetails> _details(String roomId) async =>
    MatrixSdkRoomDetails(
      roomId: roomId,
      name: 'Native room',
      topic: 'SDK-backed settings',
      avatarUrl: 'mxc://example.org/avatar',
      canonicalAlias: '#native:example.org',
      joinRule: 'invite',
      encryptionEnabled: true,
      historyVisibility: 'joined',
      notificationMode: 'allMessages',
      isDirect: false,
      directUserIds: const <String>['@bob:example.org'],
    );
