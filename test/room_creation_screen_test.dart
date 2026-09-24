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

  testWidgets('direct conversation searches people and selects a Matrix user', (
    tester,
  ) async {
    final fixture = _fixture(
      userSearchResults: const <KiteUserSearchResult>[
        KiteUserSearchResult(
          userId: '@bob:example.org',
          displayName: 'Bob Builder',
          avatarUrl: null,
        ),
      ],
    );
    KiteCreatedRoom? created;
    await tester.pumpWidget(
      _app(
        fixture.coordinator,
        mode: RoomCreationMode.directMessage,
        onCreated: (room) => created = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('room-create-user-id')), 'bob');
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-create-user-results')), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@bob:example.org'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-create-user-result-0')));
    await tester.pump();

    expect(created?.isDirect, isTrue);
    expect(created?.displayName, '@bob:example.org');
    expect(
      fixture.rooms.invocations
          .where(
            (entry) => entry.type == RoomManagementInvocationType.searchUsers,
          )
          .single
          .text,
      'bob',
    );
    expect(
      fixture.rooms.invocations
          .firstWhere(
            (entry) => entry.type == RoomManagementInvocationType.create,
          )
          .creation!
          .invitees,
      <String>['@bob:example.org'],
    );
  });

  testWidgets('people search can create a private room with an invitee', (
    tester,
  ) async {
    final fixture = _fixture(
      userSearchResults: const <KiteUserSearchResult>[
        KiteUserSearchResult(
          userId: '@bob:example.org',
          displayName: 'Bob Builder',
          avatarUrl: null,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(fixture.coordinator, mode: RoomCreationMode.directMessage),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('room-create-user-id')), 'bob');
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-create-user-private-0')));
    await tester.pumpAndSettle();

    final mode = tester.widget<SegmentedButton<RoomCreationMode>>(
      find.byKey(const Key('room-creation-mode')),
    );
    expect(mode.selected, <RoomCreationMode>{RoomCreationMode.privateRoom});
    expect(
      find.byKey(const Key('room-create-private-invitee')),
      findsOneWidget,
    );
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@bob:example.org'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Bob and me',
    );
    await tester.drag(
      find.byKey(const Key('room-creation-form')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pump();

    final request = fixture.rooms.invocations
        .firstWhere(
          (entry) => entry.type == RoomManagementInvocationType.create,
        )
        .creation!;
    expect(request.kind, KiteRoomCreationKind.privateRoom);
    expect(request.name, 'Bob and me');
    expect(request.invitees, <String>['@bob:example.org']);
  });

  testWidgets('new conversation defaults to focused cached people search', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomCreationScreen(
          coordinator: fixture.coordinator,
          recentPeople: const <KiteUserSearchResult>[
            KiteUserSearchResult(
              userId: '@nik:example.org',
              displayName: 'Nik',
              avatarUrl: null,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mode = tester.widget<SegmentedButton<RoomCreationMode>>(
      find.byKey(const Key('room-creation-mode')),
    );
    expect(mode.selected, <RoomCreationMode>{RoomCreationMode.directMessage});
    final field = find.byKey(const Key('room-create-user-id'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(find.text('Nik'), findsOneWidget);
    expect(
      fixture.rooms.invocations.where(
        (entry) => entry.type == RoomManagementInvocationType.searchUsers,
      ),
      isEmpty,
    );

    await tester.enterText(field, 'n');
    await tester.pump();
    expect(find.text('Nik'), findsOneWidget);
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

  testWidgets('private room creation defaults to no Space', (tester) async {
    final fixture = _fixture();
    const spaces = <RoomCreationSpaceOption>[
      RoomCreationSpaceOption(roomId: '!kite:example.org', name: 'Kite'),
    ];
    await tester.pumpWidget(_app(fixture.coordinator, availableSpaces: spaces));
    await tester.pump();

    expect(find.byKey(const Key('room-create-space')), findsOneWidget);
    expect(find.text('No Space'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Spaceless room',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('room-create-submit')),
      find.byKey(const Key('room-creation-form')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('room-create-submit'));
    await Scrollable.ensureVisible(
      tester.element(submit),
      alignment: 0.85,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
    await tester.pump();

    expect(fixture.rooms.invocations.last.creation?.parentSpaceId, isNull);
  });

  testWidgets('private room creation can choose a joined Space', (
    tester,
  ) async {
    final fixture = _fixture();
    const spaces = <RoomCreationSpaceOption>[
      RoomCreationSpaceOption(roomId: '!kite:example.org', name: 'Kite'),
      RoomCreationSpaceOption(roomId: '!people:example.org', name: 'People'),
    ];
    await tester.pumpWidget(_app(fixture.coordinator, availableSpaces: spaces));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('room-create-space')));
    await tester.tap(find.text('Kite').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Space room',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('room-create-submit')),
      find.byKey(const Key('room-creation-form')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('room-create-submit'));
    await Scrollable.ensureVisible(
      tester.element(submit),
      alignment: 0.85,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
    await tester.pump();

    expect(
      fixture.rooms.invocations.last.creation?.parentSpaceId,
      '!kite:example.org',
    );
  });

  testWidgets('direct mode hides a previously selected Space link', (
    tester,
  ) async {
    final fixture = _fixture();
    const spaces = <RoomCreationSpaceOption>[
      RoomCreationSpaceOption(roomId: '!kite:example.org', name: 'Kite'),
    ];
    await tester.pumpWidget(_app(fixture.coordinator, availableSpaces: spaces));
    await tester.pump();

    await tester.tap(find.text('Kite').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('room-creation-form')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This room will be linked to the selected Space.'),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('room-creation-form')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();

    expect(
      find.text('This room will be linked to the selected Space.'),
      findsNothing,
    );
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
    await tester.dragUntilVisible(
      find.byKey(const Key('room-create-submit')),
      find.byKey(const Key('room-creation-form')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('room-create-submit'));
    await Scrollable.ensureVisible(
      tester.element(submit),
      alignment: 0.85,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
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
  List<RoomCreationSpaceOption> availableSpaces =
      const <RoomCreationSpaceOption>[],
  ValueChanged<KiteCreatedRoom>? onCreated,
}) => MaterialApp(
  theme: KiteTheme.light,
  home: RoomCreationScreen(
    coordinator: coordinator,
    initialMode: mode,
    availableSpaces: availableSpaces,
    onCreated: onCreated,
  ),
);

_RoomFixture _fixture({
  KiteRoomCapabilities? capabilities,
  Iterable<KiteUserSearchResult> userSearchResults =
      const <KiteUserSearchResult>[],
}) {
  final rooms = DeterministicRoomManagementPort(
    roomCapabilities: capabilities,
    userSearchResults: userSearchResults,
  );
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
