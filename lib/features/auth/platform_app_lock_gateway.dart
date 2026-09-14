import 'package:flutter/services.dart';
import 'package:kite/features/auth/app_lock_controller.dart';

final class PlatformAppLockGateway
    implements AppLockCredentialGateway, BiometricAuthenticationGateway {
  PlatformAppLockGateway([
    this._channel = const MethodChannel('nz.presley.kite/app_lock'),
  ]);

  final MethodChannel _channel;

  @override
  Future<AppLockSettings> loadSettings() async {
    final payload = await _channel.invokeMapMethod<String, Object?>(
      'loadSettings',
    );
    if (payload == null) {
      throw StateError('Platform app lock settings were unavailable.');
    }

    return AppLockSettings(
      enabled: _requiredBool(payload, 'enabled'),
      biometricsEnabled: _requiredBool(payload, 'biometricsEnabled'),
      hideNotificationContents: _requiredBool(
        payload,
        'hideNotificationContents',
      ),
    );
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    await _channel.invokeMethod<void>('enablePin', <String, Object?>{
      'pin': pin,
      ..._settingsPayload(settings),
    });
  }

  @override
  Future<bool> verifyPin(String pin) async {
    return await _channel.invokeMethod<bool>('verifyPin', <String, Object?>{
          'pin': pin,
        }) ??
        false;
  }

  @override
  Future<void> disable() async {
    await _channel.invokeMethod<void>('disable');
  }

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    await _channel.invokeMethod<void>(
      'saveSettings',
      _settingsPayload(settings),
    );
  }

  @override
  Future<bool> isAvailable() async {
    return await _channel.invokeMethod<bool>('isBiometricAvailable') ?? false;
  }

  @override
  Future<bool> authenticate() async {
    return await _channel.invokeMethod<bool>('authenticateBiometric') ?? false;
  }

  static Map<String, Object?> _settingsPayload(AppLockSettings settings) =>
      <String, Object?>{
        'enabled': settings.enabled,
        'biometricsEnabled': settings.biometricsEnabled,
        'hideNotificationContents': settings.hideNotificationContents,
      };

  static bool _requiredBool(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is bool) return value;
    throw StateError('Platform app lock settings were invalid.');
  }
}
