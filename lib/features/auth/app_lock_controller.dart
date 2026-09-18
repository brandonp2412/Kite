import 'package:kite/core/async_controller_lifecycle.dart';
import 'package:signals/signals.dart';

final class AppLockSettings {
  const AppLockSettings({
    required this.enabled,
    required this.biometricsEnabled,
    required this.hideNotificationContents,
  });

  const AppLockSettings.disabled()
    : enabled = false,
      biometricsEnabled = false,
      hideNotificationContents = false;

  final bool enabled;
  final bool biometricsEnabled;
  final bool hideNotificationContents;

  AppLockSettings copyWith({
    bool? enabled,
    bool? biometricsEnabled,
    bool? hideNotificationContents,
  }) {
    return AppLockSettings(
      enabled: enabled ?? this.enabled,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      hideNotificationContents:
          hideNotificationContents ?? this.hideNotificationContents,
    );
  }
}

abstract interface class AppLockCredentialGateway {
  Future<AppLockSettings> loadSettings();

  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  });

  Future<bool> verifyPin(String pin);

  Future<void> disable();

  Future<void> saveSettings(AppLockSettings settings);
}

abstract interface class BiometricAuthenticationGateway {
  Future<bool> isAvailable();

  Future<bool> authenticate();
}

final class AppLockController with AsyncControllerLifecycle {
  AppLockController(this._credentials, this._biometrics);

  final AppLockCredentialGateway _credentials;
  final BiometricAuthenticationGateway _biometrics;

  final settings = signal(const AppLockSettings.disabled());
  final isLocked = signal(false);
  final isBusy = signal(false);
  final isReady = signal(false);
  final errorMessage = signal<String?>(null);

  bool get shouldHideNotificationContents =>
      !isReady.value ||
      (isLocked.value && settings.value.hideNotificationContents);

  Future<void> load() async {
    if (controllerDisposed || isBusy.value) return;
    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    isReady.value = false;
    errorMessage.value = null;
    try {
      final loaded = await _credentials.loadSettings();
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      if (!_isValidSettings(loaded)) {
        throw StateError('Invalid app lock settings.');
      }
      settings.value = loaded;
      isLocked.value = loaded.enabled;
      isReady.value = true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        settings.value = const AppLockSettings.disabled();
        isLocked.value = true;
        errorMessage.value = 'Kite could not load app lock settings.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  Future<void> enableWithPin({
    required String pin,
    required bool hideNotificationContents,
  }) async {
    if (controllerDisposed || isBusy.value) return;
    if (settings.value.enabled) {
      errorMessage.value = 'App lock is already enabled.';
      return;
    }
    if (!_isValidPin(pin)) {
      errorMessage.value = 'Use a PIN with 4 to 64 digits.';
      return;
    }

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = AppLockSettings(
        enabled: true,
        biometricsEnabled: false,
        hideNotificationContents: hideNotificationContents,
      );
      await _credentials.enablePin(pin: pin, settings: next);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      settings.value = next;
      isLocked.value = true;
      isReady.value = true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not enable app lock securely.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    if (controllerDisposed || isBusy.value || !settings.value.enabled) return;

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      if (enabled) {
        final available = await _biometrics.isAvailable();
        if (!isControllerLifecycleCurrent(lifecycle)) return;
        if (!available) {
          errorMessage.value =
              'Biometric unlock is not available on this device.';
          return;
        }
      }
      final next = settings.value.copyWith(biometricsEnabled: enabled);
      await _credentials.saveSettings(next);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      settings.value = next;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not update biometric unlock.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  Future<void> setHideNotificationContents(bool hidden) async {
    if (controllerDisposed || isBusy.value || !settings.value.enabled) return;

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = settings.value.copyWith(hideNotificationContents: hidden);
      await _credentials.saveSettings(next);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      settings.value = next;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not update notification privacy.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  void lock() {
    if (controllerDisposed || !settings.value.enabled) return;
    errorMessage.value = null;
    isLocked.value = true;
  }

  Future<bool> unlockWithPin(String pin) async {
    if (controllerDisposed || isBusy.value || !settings.value.enabled) {
      return false;
    }
    if (!_isValidPin(pin)) {
      errorMessage.value = 'Enter your app lock PIN.';
      return false;
    }

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final unlocked = await _credentials.verifyPin(pin);
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      if (!unlocked) {
        errorMessage.value = 'Incorrect PIN.';
        return false;
      }
      isLocked.value = false;
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not verify your PIN.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (controllerDisposed ||
        isBusy.value ||
        !settings.value.enabled ||
        !settings.value.biometricsEnabled) {
      return false;
    }

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final unlocked = await _biometrics.authenticate();
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      if (!unlocked) {
        errorMessage.value = 'Biometric unlock was not accepted.';
        return false;
      }
      isLocked.value = false;
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not use biometric unlock.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  Future<void> disable(String pin) async {
    if (controllerDisposed || isBusy.value || !settings.value.enabled) return;
    if (!_isValidPin(pin)) {
      errorMessage.value = 'Enter your app lock PIN.';
      return;
    }

    final lifecycle = captureControllerLifecycle();
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final verified = await _credentials.verifyPin(pin);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      if (!verified) {
        errorMessage.value = 'Incorrect PIN.';
        return;
      }
      await _credentials.disable();
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      const next = AppLockSettings.disabled();
      settings.value = next;
      isLocked.value = false;
      isReady.value = true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not disable app lock securely.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isBusy.value = false;
      }
    }
  }

  bool _isValidPin(String pin) =>
      pin.length <= 64 && RegExp(r'^\d{4,}$').hasMatch(pin);

  bool _isValidSettings(AppLockSettings candidate) =>
      candidate.enabled ||
      (!candidate.biometricsEnabled && !candidate.hideNotificationContents);

  void dispose() {
    if (!disposeControllerLifecycle()) return;
    settings.dispose();
    isLocked.dispose();
    isBusy.dispose();
    isReady.dispose();
    errorMessage.dispose();
  }
}
