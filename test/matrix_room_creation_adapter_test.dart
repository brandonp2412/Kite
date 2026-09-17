import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/matrix_room_creation_adapter.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  test(
    'production room creation adapter preserves Matrix room semantics',
    () async {
      MatrixSdkRoomCreationRequest? captured;
      final port = MatrixRoomCreationManagementPort((request) async {
        captured = request;
        return const MatrixSdkCreatedRoom(
          roomId: '!created:example.org',
          isDirect: false,
        );
      });

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
      );

      final capabilities = await port.capabilities();

      expect(capabilities.canCreatePublicRooms, isTrue);
      expect(capabilities.supportedJoinRules, <KiteRoomJoinRule>{
        KiteRoomJoinRule.invite,
        KiteRoomJoinRule.public,
      });
    },
  );
}
