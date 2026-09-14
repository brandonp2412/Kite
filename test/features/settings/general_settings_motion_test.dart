import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/settings/general_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class _DeferredSettingsGateway implements SettingsGateway {
  final appearanceSave = Completer<void>();

  @override
  Future<KiteSettings> load() async => const KiteSettings.defaults();

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) {
    return appearanceSave.future;
  }

  @override
  Future<void> saveLanguage(String? languageTag) async {}

  @override
  Future<void> saveNotificationMaster(bool enabled) async {}

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
    'appearance save keeps general settings geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
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
          home: GeneralSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );

      final list = find.byKey(const Key('general-settings-list'));
      final languagePicker = find.byKey(const Key('language-picker'));
      final initialList = _rectOf(tester, list);
      final initialLanguagePicker = _rectOf(tester, languagePicker);

      await tester.tap(find.byKey(const Key('appearance-dark')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, languagePicker), initialLanguagePicker);
        expect(tester.takeException(), isNull);
      }

      gateway.appearanceSave.complete();
      await tester.pump();
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, languagePicker), initialLanguagePicker);
      expect(controller.settings.value.appearanceMode, KiteAppearanceMode.dark);
    },
  );
}
