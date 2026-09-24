import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_creation_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

Rect _rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  testWidgets(
    'room creation mode and validation preserve shell geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final rooms = DeterministicRoomManagementPort();
      final coordinator = RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: DeterministicDirectRoomMetadataPort(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: RoomCreationScreen(
            coordinator: coordinator,
            initialMode: RoomCreationMode.directMessage,
            availableSpaces: const <RoomCreationSpaceOption>[
              RoomCreationSpaceOption(
                roomId: '!kite:example.org',
                name: 'Kite',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final appBar = find.byType(AppBar);
      final mode = find.byKey(const Key('room-creation-mode'));
      final errorSlot = find.byKey(const Key('room-create-error-slot'));
      final appBarRect = _rectOf(tester, appBar);
      final modeRect = _rectOf(tester, mode);
      final errorRect = _rectOf(tester, errorSlot);

      await tester.enterText(
        find.byKey(const Key('room-create-user-id')),
        'invalid',
      );
      await tester.tap(find.byKey(const Key('room-create-submit')));
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, appBar), appBarRect);
        expect(_rectOf(tester, mode), modeRect);
        expect(_rectOf(tester, errorSlot), errorRect);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('Private'));
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, appBar), appBarRect);
        expect(_rectOf(tester, mode), modeRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('room-create-name')), findsOneWidget);
      final spacePicker = find.byKey(const Key('room-create-space'));
      expect(spacePicker, findsOneWidget);
      await tester.tap(find.text('Kite').last);
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, appBar), appBarRect);
        expect(_rectOf(tester, mode), modeRect);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
