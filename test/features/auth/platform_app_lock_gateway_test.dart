import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/platform_app_lock_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nz.presley.kite/app_lock_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'loads platform settings and persists only explicit app-lock fields',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'loadSettings') {
          return <String, Object?>{
            'enabled': true,
            'biometricsEnabled': false,
            'hideNotificationContents': true,
          };
        }
        return null;
      });
      final gateway = PlatformAppLockGateway(channel);

      final settings = await gateway.loadSettings();
      await gateway.saveSettings(settings.copyWith(biometricsEnabled: true));

      expect(settings.enabled, isTrue);
      expect(settings.biometricsEnabled, isFalse);
      expect(settings.hideNotificationContents, isTrue);
      expect(calls.map((call) => call.method), <String>[
        'loadSettings',
        'saveSettings',
      ]);
      expect(calls.last.arguments, <String, Object?>{
        'enabled': true,
        'biometricsEnabled': true,
        'hideNotificationContents': true,
      });
    },
  );

  test(
    'PIN crosses the platform boundary only for enrollment and verification',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'verifyPin') return true;
        return null;
      });
      final gateway = PlatformAppLockGateway(channel);
      const settings = AppLockSettings(
        enabled: true,
        biometricsEnabled: false,
        hideNotificationContents: true,
      );

      await gateway.enablePin(pin: '4826', settings: settings);
      expect(await gateway.verifyPin('4826'), isTrue);
      await gateway.disable();

      expect(calls.map((call) => call.method), <String>[
        'enablePin',
        'verifyPin',
        'disable',
      ]);
      expect((calls.first.arguments as Map<Object?, Object?>)['pin'], '4826');
      expect((calls[1].arguments as Map<Object?, Object?>)['pin'], '4826');
      expect(calls.last.arguments, isNull);
    },
  );

  test(
    'biometric methods use boolean platform results and fail closed on null',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'isBiometricAvailable' => true,
          'authenticateBiometric' => null,
          _ => null,
        };
      });
      final gateway = PlatformAppLockGateway(channel);

      expect(await gateway.isAvailable(), isTrue);
      expect(await gateway.authenticate(), isFalse);
    },
  );

  test('rejects malformed settings returned by the platform', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'enabled': true,
        'biometricsEnabled': 'yes',
        'hideNotificationContents': true,
      };
    });
    final gateway = PlatformAppLockGateway(channel);

    expect(gateway.loadSettings(), throwsStateError);
  });
}
