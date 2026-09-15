import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_settings_screen.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

const _roomId = '!settings-motion:example.org';

Rect _rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  testWidgets(
    'room setting mutation and validation preserve shell geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final rooms = DeterministicRoomManagementPort();
      rooms.detailsByRoomId[_roomId] = KiteRoomDetails(
        roomId: _roomId,
        name: 'Community',
        topic: 'Stable settings fixture',
        avatarUrl: null,
        canonicalAlias: '#community:example.org',
        joinRule: KiteRoomJoinRule.invite,
        encryptionEnabled: false,
        historyVisibility: KiteRoomHistoryVisibility.joined,
        notificationMode: KiteRoomNotificationMode.allMessages,
        isDirect: false,
        directUserIds: const <String>{},
      );
      final coordinator = RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: DeterministicDirectRoomMetadataPort(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: RoomSettingsScreen(roomId: _roomId, coordinator: coordinator),
        ),
      );
      await tester.pumpAndSettle();

      final appBar = find.byType(AppBar);
      final name = find.byKey(const Key('room-settings-name'));
      final errorSlot = find.byKey(const Key('room-settings-error-slot'));
      final save = find.byKey(const Key('room-settings-save'));
      final appBarRect = _rectOf(tester, appBar);
      final nameRect = _rectOf(tester, name);
      final errorRect = _rectOf(tester, errorSlot);
      final saveRect = _rectOf(tester, save);

      await tester.enterText(
        find.byKey(const Key('room-settings-alias')),
        'invalid alias',
      );
      await tester.tap(save);
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, appBar), appBarRect);
        expect(_rectOf(tester, name), nameRect);
        expect(_rectOf(tester, errorSlot), errorRect);
        expect(_rectOf(tester, save), saveRect);
        expect(tester.takeException(), isNull);
      }
      expect(
        find.text('A canonical room alias must look like #room:server.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('room-settings-encryption')));
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, appBar), appBarRect);
        expect(_rectOf(tester, name), nameRect);
        expect(_rectOf(tester, errorSlot), errorRect);
        expect(_rectOf(tester, save), saveRect);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
