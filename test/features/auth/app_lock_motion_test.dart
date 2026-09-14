import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_unlock_screen.dart';
import 'package:kite/features/settings/app_lock_settings_screen.dart';

final class _DeferredSettingsCredentials implements AppLockCredentialGateway {
  final save = Completer<void>();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {}

  @override
  Future<AppLockSettings> loadSettings() async => const AppLockSettings(
    enabled: true,
    biometricsEnabled: false,
    hideNotificationContents: true,
  );

  @override
  Future<void> saveSettings(AppLockSettings settings) => save.future;

  @override
  Future<bool> verifyPin(String pin) async => true;
}

final class _DeferredUnlockCredentials implements AppLockCredentialGateway {
  final verification = Completer<bool>();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {}

  @override
  Future<AppLockSettings> loadSettings() async => const AppLockSettings(
    enabled: true,
    biometricsEnabled: false,
    hideNotificationContents: true,
  );

  @override
  Future<void> saveSettings(AppLockSettings settings) async {}

  @override
  Future<bool> verifyPin(String pin) => verification.future;
}

final class _NoBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<bool> isAvailable() async => false;
}

final class _DeferredBiometrics implements BiometricAuthenticationGateway {
  final authentication = Completer<bool>();

  @override
  Future<bool> authenticate() => authentication.future;

  @override
  Future<bool> isAvailable() async => true;
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void _configure120Hz(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  final display = tester.binding.platformDispatcher.displays.first;
  display.refreshRate = PerformanceContract.motionRefreshRateHz;
}

void _reset120Hz(WidgetTester tester) {
  tester.view.resetDevicePixelRatio();
  tester.view.resetPhysicalSize();
  tester.binding.platformDispatcher.displays.first.resetRefreshRate();
}

void main() {
  testWidgets(
    'app lock preference save keeps settings geometry stable at 120 Hz',
    (tester) async {
      _configure120Hz(tester);
      addTearDown(() => _reset120Hz(tester));

      final credentials = _DeferredSettingsCredentials();
      final controller = AppLockController(credentials, _NoBiometrics());
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: AppLockSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );

      final list = find.byKey(const Key('app-lock-settings-list'));
      final privacy = find.byKey(const Key('app-lock-hide-notifications'));
      final initialList = _rectOf(tester, list);
      final initialPrivacy = _rectOf(tester, privacy);

      await tester.tap(privacy);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, privacy), initialPrivacy);
        expect(tester.takeException(), isNull);
      }

      credentials.save.complete();
      await tester.pump();
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, privacy), initialPrivacy);
      expect(controller.settings.value.hideNotificationContents, isFalse);
    },
  );

  testWidgets('biometric verification keeps unlock geometry stable at 120 Hz', (
    tester,
  ) async {
    _configure120Hz(tester);
    addTearDown(() => _reset120Hz(tester));

    final credentials = _DeferredUnlockCredentials();
    final biometrics = _DeferredBiometrics();
    final controller = AppLockController(credentials, biometrics);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.setBiometricsEnabled(true);
    await tester.pumpWidget(
      MaterialApp(home: AppUnlockScreen(controller: controller)),
    );

    final heading = find.byKey(const Key('app-unlock-heading'));
    final subtitle = find.byKey(const Key('app-unlock-subtitle'));
    final initialHeading = _rectOf(tester, heading);
    final initialSubtitle = _rectOf(tester, subtitle);

    await tester.tap(find.byKey(const Key('app-unlock-biometrics')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, heading), initialHeading);
      expect(_rectOf(tester, subtitle), initialSubtitle);
      expect(tester.takeException(), isNull);
    }

    biometrics.authentication.complete(true);
    await tester.pump();
    expect(_rectOf(tester, heading), initialHeading);
    expect(_rectOf(tester, subtitle), initialSubtitle);
    expect(controller.isLocked.value, isFalse);
  });

  testWidgets('PIN verification keeps unlock geometry stable at 120 Hz', (
    tester,
  ) async {
    _configure120Hz(tester);
    addTearDown(() => _reset120Hz(tester));

    final credentials = _DeferredUnlockCredentials();
    final controller = AppLockController(credentials, _NoBiometrics());
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(home: AppUnlockScreen(controller: controller)),
    );

    final heading = find.byKey(const Key('app-unlock-heading'));
    final subtitle = find.byKey(const Key('app-unlock-subtitle'));
    final initialHeading = _rectOf(tester, heading);
    final initialSubtitle = _rectOf(tester, subtitle);

    await tester.enterText(find.byKey(const Key('app-unlock-pin')), '1234');
    await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, heading), initialHeading);
      expect(_rectOf(tester, subtitle), initialSubtitle);
      expect(tester.takeException(), isNull);
    }

    credentials.verification.complete(true);
    await tester.pump();
    expect(_rectOf(tester, heading), initialHeading);
    expect(_rectOf(tester, subtitle), initialSubtitle);
    expect(controller.isLocked.value, isFalse);
  });
}
