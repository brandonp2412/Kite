import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/notifications/app_lock_notification_privacy.dart';

final class _PrivacyCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings.disabled();
  String? pin;

  @override
  Future<void> disable() async {
    pin = null;
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

final class _PrivacyBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  test(
    'notification privacy follows restored and runtime app-lock state',
    () async {
      final credentials = _PrivacyCredentials();
      final controller = AppLockController(credentials, _PrivacyBiometrics());
      final privacy = AppLockNotificationPrivacy(controller);
      addTearDown(controller.dispose);

      expect(privacy.hideNotificationContents, isTrue);

      await controller.load();
      expect(privacy.hideNotificationContents, isFalse);

      await controller.enableWithPin(
        pin: '1234',
        hideNotificationContents: true,
      );
      expect(privacy.hideNotificationContents, isTrue);

      expect(await controller.unlockWithPin('1234'), isTrue);
      expect(privacy.hideNotificationContents, isFalse);

      controller.lock();
      expect(privacy.hideNotificationContents, isTrue);
    },
  );
}
