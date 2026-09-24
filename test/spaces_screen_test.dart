import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/home/spaces_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

void main() {
  testWidgets('dedicated Spaces area browses joined and discoverable rooms', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = SpacesController();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spaces-screen')), findsOneWidget);
    expect(find.byKey(const Key('space-title-kite-space')), findsOneWidget);
    expect(
      find.byKey(const Key('space-room-row-kite-release')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('space-room-join-kite-release')),
      findsOneWidget,
    );
    expect(find.text('Joined'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('spaces-chip-people-space')));
    await tester.pump();
    expect(controller.selectedSpaceId.value, 'people-space');
    expect(find.byKey(const Key('space-title-people-space')), findsOneWidget);
    expect(find.byKey(const Key('space-room-row-coffee-club')), findsOneWidget);

    await tester.tap(find.byKey(const Key('space-room-join-coffee-club')));
    await tester.pump();
    expect(
      controller.joinStateFor('coffee-club').value,
      SpaceRoomJoinState.joining,
    );
    expect(find.byKey(const Key('space-room-joining')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(
      controller.joinStateFor('coffee-club').value,
      SpaceRoomJoinState.joined,
    );
    expect(find.byKey(const Key('space-room-join-coffee-club')), findsNothing);
  });

  testWidgets('Spaces area creates a production-shaped public Space', (
    tester,
  ) async {
    final rooms = DeterministicRoomManagementPort();
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(
          controller: SpacesController(),
          roomCreation: coordinator,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('spaces-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('space-create-name')),
      'Kite Community',
    );
    await tester.enterText(
      find.byKey(const Key('space-create-topic')),
      'Project rooms',
    );
    await tester.tap(find.byKey(const Key('space-create-public')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('space-create-submit')));
    await tester.pumpAndSettle();

    final request = rooms.invocations.last.creation!;
    expect(request.kind, KiteRoomCreationKind.space);
    expect(request.name, 'Kite Community');
    expect(request.topic, 'Project rooms');
    expect(request.joinRule, KiteRoomJoinRule.public);
    expect(request.encryptionEnabled, isFalse);
    expect(find.text('Kite Community created'), findsOneWidget);
  });

  testWidgets('Spaces area creates a room inside the selected Matrix Space', (
    tester,
  ) async {
    const space = SpaceSummary(
      id: '!kite:example.org',
      name: 'Kite',
      description: 'Project Space',
      memberCount: 4,
      rooms: <SpaceRoomPreview>[],
    );
    final controller = SpacesController(spaces: const <SpaceSummary>[space]);
    final rooms = DeterministicRoomManagementPort();
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller, roomCreation: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('spaces-create-room')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-create-name')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Roadmap',
    );
    await tester.ensureVisible(find.byKey(const Key('room-create-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pumpAndSettle();

    final request = rooms.invocations.last.creation!;
    expect(request.kind, KiteRoomCreationKind.privateRoom);
    expect(request.name, 'Roadmap');
    expect(request.parentSpaceId, '!kite:example.org');
    expect(find.text('Roadmap created in Kite'), findsOneWidget);
  });

  testWidgets('Spaces area manages the selected Space through room settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const space = SpaceSummary(
      id: '!kite:example.org',
      name: 'Kite',
      description: 'Project Space',
      memberCount: 4,
      rooms: <SpaceRoomPreview>[],
    );
    final controller = SpacesController(spaces: const <SpaceSummary>[space]);
    final rooms = DeterministicRoomManagementPort();
    rooms.detailsByRoomId[space.id] = KiteRoomDetails(
      roomId: space.id,
      name: space.name,
      topic: space.description,
      avatarUrl: null,
      canonicalAlias: null,
      joinRule: KiteRoomJoinRule.invite,
      encryptionEnabled: false,
      historyVisibility: KiteRoomHistoryVisibility.shared,
      notificationMode: KiteRoomNotificationMode.allMessages,
      isDirect: false,
      directUserIds: const <String>[],
    );
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller, roomCreation: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('spaces-manage')));
    await tester.pumpAndSettle();
    expect(find.text('Space settings'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('room-settings-name')),
      'Kite Community',
    );
    await tester.enterText(
      find.byKey(const Key('room-settings-topic')),
      'Project rooms and releases',
    );
    await tester.ensureVisible(find.byKey(const Key('room-settings-save')));
    await tester.tap(find.byKey(const Key('room-settings-save')));
    await tester.pump();

    expect(
      rooms.invocations.any(
        (call) =>
            call.type == RoomManagementInvocationType.setName &&
            call.roomId == space.id &&
            call.text == 'Kite Community',
      ),
      isTrue,
    );
    expect(
      rooms.invocations.any(
        (call) =>
            call.type == RoomManagementInvocationType.setTopic &&
            call.roomId == space.id &&
            call.text == 'Project rooms and releases',
      ),
      isTrue,
    );
    expect(controller.selectedSpace?.name, 'Kite Community');
    expect(controller.selectedSpace?.description, 'Project rooms and releases');
  });

  test('controller rejects unknown Spaces and preserves joined room state', () {
    final controller = SpacesController();
    expect(() => controller.selectSpace('missing-space'), throwsArgumentError);
    expect(controller.joinStateFor('kite').value, SpaceRoomJoinState.joined);
    expect(() => controller.joinStateFor('missing-room'), throwsArgumentError);
  });
  testWidgets('desktop Spaces layout uses a stable navigation rail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = SpacesController();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spaces-rail')), findsOneWidget);
    expect(find.byKey(const Key('spaces-chip-row')), findsNothing);
    expect(find.byKey(const Key('space-body-kite-space')), findsOneWidget);

    final headerRect = tester.getRect(find.byKey(const Key('spaces-header')));
    await tester.tap(find.byKey(const Key('spaces-rail-people-space')));
    await tester.pump();

    expect(find.byKey(const Key('space-body-people-space')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('spaces-header'))), headerRect);
  });
}
