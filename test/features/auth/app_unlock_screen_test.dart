import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_unlock_screen.dart';

final class _FakeAppLockCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings.disabled();
  String? pin;

  @override
  Future<void> disable() async {}

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
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
  bool authenticated = true;
  int authenticationCalls = 0;

  @override
  Future<bool> authenticate() async {
    authenticationCalls += 1;
    return authenticated;
  }

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  testWidgets('PIN unlock rejects the wrong PIN and completes on success', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials();
    final biometrics = _FakeBiometrics();
    final controller = AppLockController(credentials, biometrics);
    addTearDown(controller.dispose);
    await controller.enableWithPin(pin: '1234', hideNotificationContents: true);
    var unlockCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppUnlockScreen(
          controller: controller,
          onUnlocked: () => unlockCalls += 1,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('app-unlock-pin')), '9999');
    await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
    await tester.pumpAndSettle();
    expect(controller.isLocked.value, isTrue);
    expect(find.text('Incorrect PIN.'), findsOneWidget);
    expect(unlockCalls, 0);

    await tester.enterText(find.byKey(const Key('app-unlock-pin')), '1234');
    await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
    await tester.pumpAndSettle();
    expect(controller.isLocked.value, isFalse);
    expect(unlockCalls, 1);
  });

  testWidgets('biometric unlock is offered only when explicitly enabled', (
    tester,
  ) async {
    final credentials = _FakeAppLockCredentials();
    final biometrics = _FakeBiometrics();
    final controller = AppLockController(credentials, biometrics);
    addTearDown(controller.dispose);
    await controller.enableWithPin(
      pin: '1234',
      hideNotificationContents: false,
    );

    await tester.pumpWidget(
      MaterialApp(home: AppUnlockScreen(controller: controller)),
    );
    expect(find.byKey(const Key('app-unlock-biometrics')), findsNothing);

    await controller.setBiometricsEnabled(true);
    controller.lock();
    await tester.pump();
    expect(find.byKey(const Key('app-unlock-biometrics')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-unlock-biometrics')));
    await tester.pumpAndSettle();
    expect(controller.isLocked.value, isFalse);
    expect(biometrics.authenticationCalls, 1);
  });
}
