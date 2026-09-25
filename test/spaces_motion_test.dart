import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/home/spaces_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() => spacesController.reset());

  testWidgets(
    'Spaces screen and join state preserve deterministic geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      spacesController.reset();
      final rooms = DeterministicRoomManagementPort();
      rooms.detailsByRoomId['kite-space'] = KiteRoomDetails(
        roomId: 'kite-space',
        name: 'Kite',
        topic: 'Kite development and release rooms',
        avatarUrl: null,
        canonicalAlias: null,
        joinRule: KiteRoomJoinRule.invite,
        encryptionEnabled: false,
        historyVisibility: KiteRoomHistoryVisibility.shared,
        notificationMode: KiteRoomNotificationMode.allMessages,
        isDirect: false,
        directUserIds: const <String>[],
      );
      final roomCreation = RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: DeterministicDirectRoomMetadataPort(),
      );
      await tester.pumpWidget(
        KiteApp(
          themeMode: ThemeMode.light,
          home: SpacesScreen(roomCreation: roomCreation),
        ),
      );
      await tester.pumpAndSettle();

      final screen = find.byKey(const Key('spaces-screen'));
      expect(screen, findsOneWidget);
      final screenRect = _rectOf(tester, screen);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, screen), screenRect);
        expect(tester.takeException(), isNull);
      }

      final header = find.byKey(const Key('spaces-header'));
      final headerRect = _rectOf(tester, header);

      await tester.tap(find.byKey(const Key('spaces-link-room')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('space-link-sheet')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('space-link-sheet'))))
          .pop();
      await tester.pumpAndSettle();
      expect(_rectOf(tester, header), headerRect);

      await tester.tap(find.byKey(const Key('spaces-manage')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-settings-screen')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('room-settings-screen'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(_rectOf(tester, header), headerRect);

      await tester.tap(find.byKey(const Key('spaces-create')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('space-create-name')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('space-create-name'))))
          .pop();
      await tester.pumpAndSettle();
      expect(_rectOf(tester, header), headerRect);

      await tester.tap(find.byKey(const Key('spaces-chip-people-space')));
      await tester.pump();
      expect(_rectOf(tester, header), headerRect);
      expect(find.byKey(const Key('space-body-people-space')), findsOneWidget);

      final slot = find.byKey(const Key('space-room-action-slot-coffee-club'));
      final row = find.byKey(const Key('space-room-row-coffee-club'));
      final slotRect = _rectOf(tester, slot);
      final rowRect = _rectOf(tester, row);
      await tester.tap(find.byKey(const Key('space-room-join-coffee-club')));
      await tester.pump();
      expect(_rectOf(tester, slot), slotRect);
      expect(_rectOf(tester, row), rowRect);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, slot), slotRect);
        expect(_rectOf(tester, row), rowRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(_rectOf(tester, slot), slotRect);
      expect(_rectOf(tester, row), rowRect);
      expect(
        spacesController.joinStateFor('coffee-club').value,
        SpaceRoomJoinState.joined,
      );
    },
  );

  testWidgets('nested Space navigation preserves frame geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

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
      KiteApp(
        themeMode: ThemeMode.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    final screen = find.byKey(const Key('spaces-screen'));
    final screenRect = _rectOf(tester, screen);
    final header = find.byKey(const Key('spaces-header'));
    final headerRect = _rectOf(tester, header);

    await tester.tap(
      find.byKey(const Key('nested-space-open-!mobile:example.org')),
    );
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, screen), screenRect);
      expect(_rectOf(tester, header), headerRect);
      expect(tester.takeException(), isNull);
    }
    expect(
      find.byKey(const Key('space-parent-!engineering:example.org')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('space-parent-!engineering:example.org')),
    );
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, screen), screenRect);
      expect(_rectOf(tester, header), headerRect);
      expect(tester.takeException(), isNull);
    }
    expect(
      find.byKey(const Key('nested-space-row-!mobile:example.org')),
      findsOneWidget,
    );
  });
}
