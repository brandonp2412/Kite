import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';

final class _FakeAppLockCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings.disabled();
  String? enrolledPin;
  Object? loadError;
  Object? disableError;
  int disableCalls = 0;

  @override
  Future<void> disable() async {
    disableCalls += 1;
    if (disableError case final error?) throw error;
    enrolledPin = null;
    stored = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    enrolledPin = pin;
    stored = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async {
    if (loadError case final error?) throw error;
    return stored;
  }

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => enrolledPin == pin;
}

final class _FakeBiometrics implements BiometricAuthenticationGateway {
  bool available = true;
  bool authenticated = true;
  int authenticationCalls = 0;

  @override
  Future<bool> authenticate() async {
    authenticationCalls += 1;
    return authenticated;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  test(
    'app lock restoration fails closed without exposing notification contents',
    () async {
      final credentials = _FakeAppLockCredentials()
        ..loadError = StateError('credential store unavailable');
      final controller = AppLockController(credentials, _FakeBiometrics());
      addTearDown(controller.dispose);

      expect(controller.isReady.value, isFalse);
      expect(controller.shouldHideNotificationContents, isTrue);

      await controller.load();

      expect(controller.isReady.value, isFalse);
      expect(controller.isLocked.value, isTrue);
      expect(controller.shouldHideNotificationContents, isTrue);
      expect(
        controller.errorMessage.value,
        'Kite could not load app lock settings.',
      );

      credentials.loadError = null;
      await controller.load();
      expect(controller.isReady.value, isTrue);
      expect(controller.isLocked.value, isFalse);
      expect(controller.shouldHideNotificationContents, isFalse);
    },
  );

  test('invalid persisted app lock combinations fail closed', () async {
    final credentials = _FakeAppLockCredentials()
      ..stored = const AppLockSettings(
        enabled: false,
        biometricsEnabled: true,
        hideNotificationContents: false,
      );
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isReady.value, isFalse);
    expect(controller.isLocked.value, isTrue);
    expect(controller.shouldHideNotificationContents, isTrue);
    expect(
      controller.errorMessage.value,
      'Kite could not load app lock settings.',
    );
  });

  test('PIN enrollment rejects unbounded credential input', () async {
    final credentials = _FakeAppLockCredentials();
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);

    await controller.enableWithPin(
      pin: '1' * 65,
      hideNotificationContents: true,
    );

    expect(credentials.enrolledPin, isNull);
    expect(controller.settings.value.enabled, isFalse);
    expect(controller.errorMessage.value, 'Use a PIN with 4 to 64 digits.');
  });

  test(
    'existing app lock cannot be re-enrolled without disabling first',
    () async {
      final credentials = _FakeAppLockCredentials();
      final controller = AppLockController(credentials, _FakeBiometrics());
      addTearDown(controller.dispose);

      await controller.enableWithPin(
        pin: '1234',
        hideNotificationContents: true,
      );
      await controller.enableWithPin(
        pin: '9876',
        hideNotificationContents: false,
      );

      expect(credentials.enrolledPin, '1234');
      expect(controller.settings.value.hideNotificationContents, isTrue);
      expect(controller.isLocked.value, isTrue);
      expect(controller.errorMessage.value, 'App lock is already enabled.');
    },
  );

  test(
    'PIN app lock validates input and redacts notifications only while locked',
    () async {
      final credentials = _FakeAppLockCredentials();
      final controller = AppLockController(credentials, _FakeBiometrics());
      addTearDown(controller.dispose);

      await controller.enableWithPin(
        pin: '12ab',
        hideNotificationContents: true,
      );
      expect(credentials.enrolledPin, isNull);
      expect(controller.errorMessage.value, 'Use a PIN with 4 to 64 digits.');

      await controller.enableWithPin(
        pin: '1234',
        hideNotificationContents: true,
      );
      expect(credentials.enrolledPin, '1234');
      expect(controller.settings.value.enabled, isTrue);
      expect(controller.isLocked.value, isTrue);
      expect(controller.shouldHideNotificationContents, isTrue);

      expect(await controller.unlockWithPin('9999'), isFalse);
      expect(controller.isLocked.value, isTrue);
      expect(await controller.unlockWithPin('1234'), isTrue);
      expect(controller.isLocked.value, isFalse);
      expect(controller.shouldHideNotificationContents, isFalse);

      controller.lock();
      expect(controller.shouldHideNotificationContents, isTrue);
    },
  );

  test(
    'biometric unlock requires explicit enablement and device availability',
    () async {
      final credentials = _FakeAppLockCredentials();
      final biometrics = _FakeBiometrics()..available = false;
      final controller = AppLockController(credentials, biometrics);
      addTearDown(controller.dispose);

      await controller.enableWithPin(
        pin: '1234',
        hideNotificationContents: false,
      );
      await controller.setBiometricsEnabled(true);

      expect(controller.settings.value.biometricsEnabled, isFalse);
      expect(
        controller.errorMessage.value,
        'Biometric unlock is not available on this device.',
      );

      biometrics.available = true;
      await controller.setBiometricsEnabled(true);
      expect(controller.settings.value.biometricsEnabled, isTrue);

      biometrics.authenticated = false;
      expect(await controller.unlockWithBiometrics(), isFalse);
      expect(controller.isLocked.value, isTrue);

      biometrics.authenticated = true;
      expect(await controller.unlockWithBiometrics(), isTrue);
      expect(controller.isLocked.value, isFalse);
      expect(biometrics.authenticationCalls, 2);
    },
  );

  test(
    'disabling app lock requires the current PIN and clears credential state',
    () async {
      final credentials = _FakeAppLockCredentials();
      final controller = AppLockController(credentials, _FakeBiometrics());
      addTearDown(controller.dispose);

      await controller.enableWithPin(
        pin: '1234',
        hideNotificationContents: true,
      );
      await controller.disable('9999');
      expect(controller.settings.value.enabled, isTrue);
      expect(controller.isLocked.value, isTrue);
      expect(credentials.disableCalls, 0);

      await controller.disable('1234');
      expect(controller.settings.value.enabled, isFalse);
      expect(controller.isLocked.value, isFalse);
      expect(credentials.disableCalls, 1);
    },
  );

  test('failed app lock disable never unlocks protected content', () async {
    final credentials = _FakeAppLockCredentials();
    final controller = AppLockController(credentials, _FakeBiometrics());
    addTearDown(controller.dispose);

    await controller.enableWithPin(pin: '1234', hideNotificationContents: true);
    credentials.disableError = StateError('credential delete failed');

    await controller.disable('1234');

    expect(controller.settings.value.enabled, isTrue);
    expect(controller.isLocked.value, isTrue);
    expect(controller.shouldHideNotificationContents, isTrue);
    expect(credentials.disableCalls, 1);
    expect(
      controller.errorMessage.value,
      'Kite could not disable app lock securely.',
    );
  });
}
