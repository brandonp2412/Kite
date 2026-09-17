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
}
