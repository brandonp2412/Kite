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

  testWidgets('Spaces area navigates joined nested Spaces and parent links', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const child = SpaceSummary(
      id: '!mobile:example.org',
      name: 'Mobile',
      description: 'Mobile clients',
      memberCount: 12,
      rooms: <SpaceRoomPreview>[],
    );
    const parent = SpaceSummary(
      id: '!engineering:example.org',
      name: 'Engineering',
      description: 'Product and engineering',
      memberCount: 42,
      rooms: <SpaceRoomPreview>[],
      childSpaceIds: <String>['!mobile:example.org'],
    );
    final controller = SpacesController(
      spaces: const <SpaceSummary>[parent, child],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nested-space-row-!mobile:example.org')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('nested-space-open-!mobile:example.org')),
    );
    await tester.pump();
    expect(controller.selectedSpaceId.value, child.id);
    expect(
      find.byKey(const Key('space-title-!mobile:example.org')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('space-parent-!engineering:example.org')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('space-parent-!engineering:example.org')),
    );
    await tester.pump();
    expect(controller.selectedSpaceId.value, parent.id);
    expect(
      find.byKey(const Key('nested-space-row-!mobile:example.org')),
      findsOneWidget,
    );
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

  testWidgets('Spaces area links an existing joined Matrix room', (
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

    await tester.tap(find.byKey(const Key('spaces-link-room')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('space-link-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('space-link-room-id')),
      '!roadmap:example.org',
    );
    await tester.tap(find.byKey(const Key('space-link-submit')));
    await tester.pumpAndSettle();

    final call = rooms.invocations.singleWhere(
      (entry) => entry.type == RoomManagementInvocationType.setSpaceChild,
    );
    expect(call.spaceId, space.id);
    expect(call.roomId, '!roadmap:example.org');
    expect(call.text, 'linked');
    expect(
      find.text('Room linked to Kite. It will appear after the next sync.'),
      findsOneWidget,
    );
  });

  testWidgets('Spaces area unlinks an existing child room immediately', (
    tester,
  ) async {
    const room = SpaceRoomPreview(
      id: '!roadmap:example.org',
      name: 'Roadmap',
      topic: 'Planning',
      memberCount: 3,
      joined: true,
    );
    const space = SpaceSummary(
      id: '!kite:example.org',
      name: 'Kite',
      description: 'Project Space',
      memberCount: 4,
      rooms: <SpaceRoomPreview>[room],
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

    expect(
      find.byKey(const Key('space-room-unlink-!roadmap:example.org')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('space-room-unlink-!roadmap:example.org')),
    );
    await tester.pumpAndSettle();

    final call = rooms.invocations.singleWhere(
      (entry) => entry.type == RoomManagementInvocationType.setSpaceChild,
    );
    expect(call.spaceId, space.id);
    expect(call.roomId, room.id);
    expect(call.text, 'unlinked');
    expect(
      find.byKey(const Key('space-room-row-!roadmap:example.org')),
      findsNothing,
    );
    expect(find.text('Roadmap removed from Kite'), findsOneWidget);
  });

  testWidgets(
    'Spaces area discovers unjoined rooms and nested Spaces from hierarchy',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
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
      rooms.spaceHierarchyBySpaceId[space.id] = <KiteSpaceHierarchyEntry>[
        KiteSpaceHierarchyEntry(
          roomId: space.id,
          name: space.name,
          topic: space.description,
          canonicalAlias: null,
          avatarUrl: null,
          joinRule: 'public',
          worldReadable: false,
          joinedMembers: 4,
          isSpace: true,
          childRoomIds: const <String>[
            '!public:example.org',
            '!knock:example.org',
            '!mobile:example.org',
          ],
        ),
        KiteSpaceHierarchyEntry(
          roomId: '!public:example.org',
          name: 'Public room',
          topic: 'Open discussion',
          canonicalAlias: '#public:example.org',
          avatarUrl: null,
          joinRule: 'public',
          worldReadable: true,
          joinedMembers: 18,
          isSpace: false,
          childRoomIds: const <String>[],
        ),
        KiteSpaceHierarchyEntry(
          roomId: '!knock:example.org',
          name: 'Request room',
          topic: 'Ask to join',
          canonicalAlias: null,
          avatarUrl: null,
          joinRule: 'knock',
          worldReadable: false,
          joinedMembers: 9,
          isSpace: false,
          childRoomIds: const <String>[],
        ),
        KiteSpaceHierarchyEntry(
          roomId: '!mobile:example.org',
          name: 'Mobile',
          topic: 'Mobile clients',
          canonicalAlias: null,
          avatarUrl: null,
          joinRule: 'public',
          worldReadable: true,
          joinedMembers: 7,
          isSpace: true,
          childRoomIds: const <String>['!android:example.org'],
        ),
      ];
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

      expect(
        rooms.invocations
            .where(
              (call) =>
                  call.type == RoomManagementInvocationType.loadSpaceHierarchy,
            )
            .single
            .spaceId,
        space.id,
      );
      expect(
        find.byKey(const Key('space-room-join-!public:example.org')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('space-room-request-!knock:example.org')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nested-space-row-!mobile:example.org')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('spaces-chip-!mobile:example.org')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('space-room-request-!knock:example.org')),
      );
      await tester.pumpAndSettle();
      expect(
        rooms.invocations.any(
          (call) =>
              call.type == RoomManagementInvocationType.requestRoomJoin &&
              call.roomId == '!knock:example.org',
        ),
        isTrue,
      );
      expect(
        find.byKey(const Key('space-room-requested-!knock:example.org')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('nested-space-open-!mobile:example.org')),
      );
      await tester.pumpAndSettle();
      expect(controller.selectedSpaceId.value, '!mobile:example.org');
      expect(
        find.byKey(const Key('space-parent-!kite:example.org')),
        findsOneWidget,
      );
      expect(find.byTooltip('External Space'), findsOneWidget);
    },
  );

  test('hierarchy overlays survive joined-Space cache reconciliation', () {
    const root = SpaceSummary(
      id: '!kite:example.org',
      name: 'Kite',
      description: 'Project Space',
      memberCount: 4,
      rooms: <SpaceRoomPreview>[],
    );
    final controller = SpacesController(spaces: const <SpaceSummary>[root]);
    controller.reconcileHierarchy(
      spaceId: root.id,
      rooms: const <SpaceRoomPreview>[
        SpaceRoomPreview(
          id: '!public:example.org',
          name: 'Public room',
          topic: 'Open discussion',
          memberCount: 18,
          joinRule: 'public',
        ),
      ],
      childSpaces: const <SpaceSummary>[
        SpaceSummary(
          id: '!mobile:example.org',
          name: 'Mobile',
          description: 'Mobile clients',
          memberCount: 7,
          rooms: <SpaceRoomPreview>[],
          external: true,
        ),
      ],
    );

    controller.reconcileSpaces(const <SpaceSummary>[
      SpaceSummary(
        id: '!kite:example.org',
        name: 'Kite renamed',
        description: 'Updated project Space',
        memberCount: 5,
        rooms: <SpaceRoomPreview>[],
      ),
    ]);

    expect(controller.spaces.single.name, 'Kite renamed');
    expect(controller.spaces.single.rooms.single.id, '!public:example.org');
    expect(controller.childSpacesFor(root.id).single.id, '!mobile:example.org');
    controller.selectSpace('!mobile:example.org');
    expect(controller.selectedSpace?.external, isTrue);
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
