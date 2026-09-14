import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/settings/notification_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class _DeferredSettingsGateway implements SettingsGateway {
  final notificationMasterSave = Completer<void>();

  @override
  Future<KiteSettings> load() async => const KiteSettings.defaults();

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {}

  @override
  Future<void> saveLanguage(String? languageTag) async {}

  @override
  Future<void> saveNotificationMaster(bool enabled) =>
      notificationMasterSave.future;

  @override
  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  }) async {}

  @override
  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  }) async {}

  @override
  Future<void> saveMessageNotificationSound(String? soundId) async {}

  @override
  Future<void> saveCallRingtone(String? soundId) async {}
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets(
    'master save keeps notification settings geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final gateway = _DeferredSettingsGateway();
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            controller: controller,
            roomId: '!kite:example.org',
            roomName: 'Kite room',
            loadOnInit: false,
          ),
        ),
      );

      final category = find.byKey(const Key('notification-category-messages'));
      final roomMode = find.byKey(const Key('room-notification-mode'));
      final status = find.byKey(const Key('notification-settings-status'));
      final categoryRect = _rectOf(tester, category);
      final roomRect = _rectOf(tester, roomMode);
      final statusRect = _rectOf(tester, status);

      await tester.tap(find.byKey(const Key('notification-master')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, category), categoryRect);
        expect(_rectOf(tester, roomMode), roomRect);
        expect(_rectOf(tester, status), statusRect);
        expect(tester.takeException(), isNull);
      }

      gateway.notificationMasterSave.complete();
      await tester.pump();

      expect(_rectOf(tester, category), categoryRect);
      expect(_rectOf(tester, roomMode), roomRect);
      expect(_rectOf(tester, status), statusRect);
      expect(controller.settings.value.notifications.masterEnabled, isFalse);
    },
  );
}
