import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_settings_screen.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

const _roomId = '!settings:example.org';

void main() {
  testWidgets('saves only changed room metadata and policy fields', (
    tester,
  ) async {
    _useTallView(tester);
    final fixture = _fixture();
    KiteRoomDetails? saved;
    await tester.pumpWidget(_app(fixture, onSaved: (value) => saved = value));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('room-settings-name')),
      '  Kite community  ',
    );
    await tester.enterText(find.byKey(const Key('room-settings-topic')), '   ');
    await tester.enterText(
      find.byKey(const Key('room-settings-alias')),
      '#kite:example.org',
    );

    await tester.tap(find.byKey(const Key('room-settings-join-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to join').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-settings-encryption')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('room-settings-history')));
    await tester.tap(find.byKey(const Key('room-settings-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members from invite').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('room-settings-notifications')),
    );
    await tester.tap(find.byKey(const Key('room-settings-notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentions only').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('room-settings-save')));
    await tester.tap(find.byKey(const Key('room-settings-save')));
    await tester.pumpAndSettle();

    expect(
      fixture.rooms.invocations
          .where(
            (entry) =>
                entry.type != RoomManagementInvocationType.details &&
                entry.type != RoomManagementInvocationType.capabilities,
          )
          .map((entry) => entry.type),
      <RoomManagementInvocationType>[
        RoomManagementInvocationType.setName,
        RoomManagementInvocationType.setTopic,
        RoomManagementInvocationType.setCanonicalAlias,
        RoomManagementInvocationType.setJoinRule,
        RoomManagementInvocationType.enableEncryption,
        RoomManagementInvocationType.setHistoryVisibility,
        RoomManagementInvocationType.setNotificationMode,
      ],
    );
    expect(saved?.name, 'Kite community');
    expect(saved?.topic, isNull);
    expect(saved?.canonicalAlias, '#kite:example.org');
    expect(saved?.joinRule, KiteRoomJoinRule.knock);
    expect(saved?.encryptionEnabled, isTrue);
    expect(saved?.historyVisibility, KiteRoomHistoryVisibility.invited);
    expect(saved?.notificationMode, KiteRoomNotificationMode.mentionsOnly);
  });

  testWidgets('direct rooms hide address and access policy controls', (
    tester,
  ) async {
    _useTallView(tester);
    final fixture = _fixture(
      details: _details(
        name: 'Alice',
        isDirect: true,
        encryptionEnabled: true,
        directUserIds: const <String>{'@alice:example.org'},
      ),
    );
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-settings-alias')), findsNothing);
    expect(find.byKey(const Key('room-settings-join-rule')), findsNothing);
    final encryption = tester.widget<SwitchListTile>(
      find.byKey(const Key('room-settings-encryption')),
    );
    expect(encryption.value, isTrue);
    expect(encryption.onChanged, isNull);

    await tester.enterText(
      find.byKey(const Key('room-settings-name')),
      'Alice Cooper',
    );
    await tester.ensureVisible(find.byKey(const Key('room-settings-save')));
    await tester.tap(find.byKey(const Key('room-settings-save')));
    await tester.pumpAndSettle();

    expect(
      fixture.rooms.invocations
          .where((entry) => entry.type == RoomManagementInvocationType.setName)
          .single
          .text,
      'Alice Cooper',
    );
    expect(
      fixture.rooms.invocations.where(
        (entry) =>
            entry.type == RoomManagementInvocationType.setCanonicalAlias ||
            entry.type == RoomManagementInvocationType.setJoinRule ||
            entry.type == RoomManagementInvocationType.enableEncryption,
      ),
      isEmpty,
    );
  });

  testWidgets('unsupported join rules are not offered', (tester) async {
    _useTallView(tester);
    final fixture = _fixture(
      capabilities: KiteRoomCapabilities(
        canCreatePublicRooms: false,
        supportedJoinRules: const <KiteRoomJoinRule>{KiteRoomJoinRule.invite},
      ),
    );
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-settings-join-rule')));
    await tester.pumpAndSettle();

    expect(find.text('Invite only'), findsWidgets);
    expect(find.text('Request to join'), findsNothing);
    expect(find.text('Members of allowed Spaces'), findsNothing);
    expect(find.text('Anyone'), findsNothing);
  });

  testWidgets('validation errors stay inside the reserved error slot', (
    tester,
  ) async {
    _useTallView(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    final slot = find.byKey(const Key('room-settings-error-slot'));
    await tester.ensureVisible(slot);
    final before = tester.getRect(slot);
    await tester.enterText(
      find.byKey(const Key('room-settings-alias')),
      'not-an-alias',
    );
    await tester.ensureVisible(find.byKey(const Key('room-settings-save')));
    await tester.tap(find.byKey(const Key('room-settings-save')));
    await tester.pump();

    expect(
      find.text('A canonical room alias must look like #room:server.'),
      findsOneWidget,
    );
    expect(tester.getRect(slot), before);
  });

  testWidgets('failed load exposes deterministic retry state', (tester) async {
    _useTallView(tester);
    final fixture = _fixture();
    fixture.rooms.failNextWith = StateError('offline');
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    expect(find.text('Kite could not load room settings.'), findsOneWidget);
    expect(find.byKey(const Key('room-settings-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-settings-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-settings-form')), findsOneWidget);
    expect(find.byKey(const Key('room-settings-name')), findsOneWidget);
  });
}

void _useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(
  _RoomSettingsFixture fixture, {
  ValueChanged<KiteRoomDetails>? onSaved,
}) {
  return MaterialApp(
    theme: KiteTheme.light,
    home: RoomSettingsScreen(
      roomId: _roomId,
      coordinator: fixture.coordinator,
      onSaved: onSaved,
    ),
  );
}

_RoomSettingsFixture _fixture({
  KiteRoomDetails? details,
  KiteRoomCapabilities? capabilities,
}) {
  final rooms = DeterministicRoomManagementPort(
    roomCapabilities:
        capabilities ??
        KiteRoomCapabilities(
          canCreatePublicRooms: true,
          supportedJoinRules: KiteRoomJoinRule.values.toSet(),
        ),
  );
  rooms.detailsByRoomId[_roomId] = details ?? _details();
  final coordinator = RoomManagementCoordinator(
    rooms: rooms,
    directMetadata: DeterministicDirectRoomMetadataPort(),
  );
  return _RoomSettingsFixture(rooms: rooms, coordinator: coordinator);
}

KiteRoomDetails _details({
  String? name = 'Community',
  bool isDirect = false,
  bool encryptionEnabled = false,
  Set<String> directUserIds = const <String>{},
}) {
  return KiteRoomDetails(
    roomId: _roomId,
    name: name,
    topic: 'Old topic',
    avatarUrl: null,
    canonicalAlias: isDirect ? null : '#community:example.org',
    joinRule: KiteRoomJoinRule.invite,
    encryptionEnabled: encryptionEnabled,
    historyVisibility: KiteRoomHistoryVisibility.joined,
    notificationMode: KiteRoomNotificationMode.allMessages,
    isDirect: isDirect,
    directUserIds: directUserIds,
  );
}

final class _RoomSettingsFixture {
  const _RoomSettingsFixture({required this.rooms, required this.coordinator});

  final DeterministicRoomManagementPort rooms;
  final RoomManagementCoordinator coordinator;
}
