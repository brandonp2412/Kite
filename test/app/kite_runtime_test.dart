import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/features/auth/app_lock_controller.dart';

final class _RuntimeCredentials implements AppLockCredentialGateway {
  _RuntimeCredentials(this.stored);

  AppLockSettings stored;
  String pin = '1234';

  @override
  Future<void> disable() async {
    stored = const AppLockSettings.disabled();
  }

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

final class _RuntimeBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  testWidgets(
    'runtime with disabled app lock exposes app content after restore',
    (tester) async {
      final controller = AppLockController(
        _RuntimeCredentials(const AppLockSettings.disabled()),
        _RuntimeBiometrics(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: controller,
          home: const Text('private home', key: Key('runtime-private-home')),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.isReady.value, isTrue);
      expect(find.byKey(const Key('runtime-private-home')), findsOneWidget);
      expect(find.byKey(const Key('app-unlock-heading')), findsNothing);
    },
  );

  testWidgets(
    'runtime with enabled app lock withholds app content until unlock',
    (tester) async {
      final controller = AppLockController(
        _RuntimeCredentials(
          const AppLockSettings(
            enabled: true,
            biometricsEnabled: false,
            hideNotificationContents: true,
          ),
        ),
        _RuntimeBiometrics(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: controller,
          home: const Text('private home', key: Key('runtime-private-home')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('runtime-private-home')), findsNothing);
      expect(find.byKey(const Key('app-unlock-heading')), findsOneWidget);
      expect(controller.shouldHideNotificationContents, isTrue);

      await tester.enterText(find.byKey(const Key('app-unlock-pin')), '1234');
      await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isFalse);
      expect(find.byKey(const Key('runtime-private-home')), findsOneWidget);
    },
  );
}
