import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_creation_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

void main() {
  testWidgets('creates an encrypted direct conversation', (tester) async {
    final fixture = _fixture();
    KiteCreatedRoom? created;
    await tester.pumpWidget(
      _app(
        fixture.coordinator,
        mode: RoomCreationMode.directMessage,
        onCreated: (room) => created = room,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('room-create-user-id')),
      '@alice:example.org',
    );
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pump();

    expect(created?.isDirect, isTrue);
    final request = fixture.rooms.invocations
        .firstWhere(
          (entry) => entry.type == RoomManagementInvocationType.create,
        )
        .creation!;
    expect(request.encryptionEnabled, isTrue);
    expect(request.invitees, <String>['@alice:example.org']);
  });

  testWidgets('private room exposes only server-supported join rules', (
    tester,
  ) async {
    final fixture = _fixture(
      capabilities: KiteRoomCapabilities(
        canCreatePublicRooms: false,
        supportedJoinRules: const <KiteRoomJoinRule>{
          KiteRoomJoinRule.invite,
          KiteRoomJoinRule.knock,
        },
      ),
    );
    await tester.pumpWidget(_app(fixture.coordinator));
    await tester.pump();

    final dropdown = tester.widget<DropdownButtonFormField<KiteRoomJoinRule>>(
      find.byKey(const Key('room-create-join-rule')),
    );
    expect(dropdown.initialValue, KiteRoomJoinRule.invite);
    await tester.tap(find.byKey(const Key('room-create-join-rule')));
    await tester.pumpAndSettle();
    expect(find.text('Request to join'), findsOneWidget);
    expect(find.text('Members of allowed Spaces'), findsNothing);
  });

  testWidgets('public mode obeys policy and forwards alias and encryption', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      _app(fixture.coordinator, mode: RoomCreationMode.publicRoom),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Community',
    );
    await tester.enterText(
      find.byKey(const Key('room-create-alias')),
      '#community:example.org',
    );
    await tester.tap(find.byKey(const Key('room-create-encryption')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('room-create-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pump();

    final request = fixture.rooms.invocations
        .firstWhere(
          (entry) => entry.type == RoomManagementInvocationType.create,
        )
        .creation!;
    expect(request.kind, KiteRoomCreationKind.publicRoom);
    expect(request.canonicalAlias, '#community:example.org');
    expect(request.encryptionEnabled, isTrue);
  });

  testWidgets('validation errors use a reserved live-region slot', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      _app(fixture.coordinator, mode: RoomCreationMode.directMessage),
    );
    await tester.pump();

    final slot = find.byKey(const Key('room-create-error-slot'));
    final before = tester.getRect(slot);
    await tester.enterText(
      find.byKey(const Key('room-create-user-id')),
      'invalid',
    );
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pump();

    expect(find.text('A valid Matrix user ID is required.'), findsOneWidget);
    expect(tester.getRect(slot), before);
  });

  testWidgets('public mode falls back to private when server disallows it', (
    tester,
  ) async {
    final fixture = _fixture(
      capabilities: const KiteRoomCapabilities.privateOnly(),
    );
    await tester.pumpWidget(
      _app(fixture.coordinator, mode: RoomCreationMode.publicRoom),
    );
    await tester.pump();

    expect(find.byKey(const Key('room-create-join-rule')), findsOneWidget);
    expect(find.byKey(const Key('room-create-alias')), findsNothing);
    expect(find.text('Create private room'), findsOneWidget);
  });
}

Widget _app(
  RoomManagementCoordinator coordinator, {
  RoomCreationMode mode = RoomCreationMode.privateRoom,
  ValueChanged<KiteCreatedRoom>? onCreated,
}) => MaterialApp(
  theme: KiteTheme.light,
  home: RoomCreationScreen(
    coordinator: coordinator,
    initialMode: mode,
    onCreated: onCreated,
  ),
);

_RoomFixture _fixture({KiteRoomCapabilities? capabilities}) {
  final rooms = DeterministicRoomManagementPort(roomCapabilities: capabilities);
  final direct = DeterministicDirectRoomMetadataPort();
  return _RoomFixture(
    rooms: rooms,
    coordinator: RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: direct,
    ),
  );
}

final class _RoomFixture {
  const _RoomFixture({required this.rooms, required this.coordinator});

  final DeterministicRoomManagementPort rooms;
  final RoomManagementCoordinator coordinator;
}
