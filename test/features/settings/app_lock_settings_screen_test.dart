import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/settings/app_lock_settings_screen.dart';

final class _FakeAppLockCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings.disabled();
  String? pin;
  int disableCalls = 0;
  Completer<void>? enableCompleter;
  Completer<void>? disableCompleter;

  @override
  Future<void> disable() async {
    disableCalls += 1;
    await disableCompleter?.future;
    pin = null;
    stored = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    await enableCompleter?.future;
    this.pin = pin;
    stored = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async => stored;

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == this.pin;
}

final class _FakeBiometrics implements BiometricAuthenticationGateway {
  bool available = true;

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => available;
}

Widget _app(AppLockController controller) {
  return MaterialApp(
    home: AppLockSettingsScreen(controller: controller, loadOnInit: false),
  );
}

void main() {
  testWidgets('enables app lock only after matching PIN confirmation', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials();
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    await tester.enterText(find.byKey(const Key('app-lock-pin')), '1234');
    await tester.enterText(
      find.byKey(const Key('app-lock-pin-confirm')),
      '4321',
    );
    await tester.tap(find.byKey(const Key('enable-app-lock')));
    await tester.pump();

    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(credentials.pin, isNull);

    await tester.enterText(
      find.byKey(const Key('app-lock-pin-confirm')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('enable-app-lock')));
    await tester.pumpAndSettle();

    expect(credentials.pin, '1234');
    expect(controller.settings.value.enabled, isTrue);
    expect(controller.settings.value.hideNotificationContents, isTrue);
    expect(find.byKey(const Key('app-lock-biometrics')), findsOneWidget);
  });

  testWidgets('clears PIN fields before enrollment completes', (tester) async {
    final credentials = _FakeAppLockCredentials()
      ..enableCompleter = Completer<void>();
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    await tester.enterText(find.byKey(const Key('app-lock-pin')), '1234');
    await tester.enterText(
      find.byKey(const Key('app-lock-pin-confirm')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('enable-app-lock')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('app-lock-pin')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('app-lock-pin-confirm')))
          .controller!
          .text,
      isEmpty,
    );
    expect(controller.isBusy.value, isTrue);

    credentials.enableCompleter!.complete();
    await tester.pumpAndSettle();
    expect(credentials.pin, '1234');
    expect(controller.settings.value.enabled, isTrue);
  });

  testWidgets('updates biometric and notification privacy preferences', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials()
      ..stored = const AppLockSettings(
        enabled: true,
        biometricsEnabled: false,
        hideNotificationContents: true,
      )
      ..pin = '1234';
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('app-lock-biometrics')));
    await tester.pumpAndSettle();
    expect(controller.settings.value.biometricsEnabled, isTrue);

    await tester.tap(find.byKey(const Key('app-lock-hide-notifications')));
    await tester.pumpAndSettle();
    expect(controller.settings.value.hideNotificationContents, isFalse);
    expect(credentials.stored.hideNotificationContents, isFalse);
  });

  testWidgets('clears the current PIN before disable completes', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials()
      ..stored = const AppLockSettings(
        enabled: true,
        biometricsEnabled: false,
        hideNotificationContents: true,
      )
      ..pin = '1234'
      ..disableCompleter = Completer<void>();
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const Key('disable-app-lock-pin')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('disable-app-lock')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('disable-app-lock-pin')))
          .controller!
          .text,
      isEmpty,
    );
    expect(controller.isBusy.value, isTrue);

    credentials.disableCompleter!.complete();
    await tester.pumpAndSettle();
    expect(controller.settings.value.enabled, isFalse);
  });

  testWidgets('requires the current PIN before disabling app lock', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials()
      ..stored = const AppLockSettings(
        enabled: true,
        biometricsEnabled: true,
        hideNotificationContents: true,
      )
      ..pin = '1234';
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const Key('disable-app-lock-pin')),
      '9999',
    );
    await tester.tap(find.byKey(const Key('disable-app-lock')));
    await tester.pumpAndSettle();

    expect(credentials.disableCalls, 0);
    expect(find.text('Incorrect PIN.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('disable-app-lock-pin')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('disable-app-lock')));
    await tester.pumpAndSettle();

    expect(credentials.disableCalls, 1);
    expect(controller.settings.value.enabled, isFalse);
    expect(find.byKey(const Key('enable-app-lock')), findsOneWidget);
  });
}
