import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/session_device_controller.dart';

final class _FakeSessionDeviceGateway implements SessionDeviceGateway {
  List<SessionDevice> loaded = const <SessionDevice>[];
  Object? loadError;
  Object? signOutError;
  final signedOutDeviceIds = <String>[];

  @override
  Future<List<SessionDevice>> loadDevices() async {
    if (loadError case final error?) throw error;
    return loaded;
  }

  @override
  Future<void> signOutDevice(String deviceId) async {
    signedOutDeviceIds.add(deviceId);
    if (signOutError case final error?) throw error;
  }
}

const _current = SessionDevice(
  deviceId: 'CURRENT',
  displayName: 'Nox',
  isCurrent: true,
  verification: SessionDeviceVerification.verified,
);

const _remote = SessionDevice(
  deviceId: 'REMOTE',
  displayName: 'Phone',
  isCurrent: false,
  verification: SessionDeviceVerification.unverified,
);

void main() {
  test(
    'loads devices with current-device and verification state intact',
    () async {
      final gateway = _FakeSessionDeviceGateway()
        ..loaded = const <SessionDevice>[_current, _remote];
      final controller = SessionDeviceController(gateway);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.devices.value, hasLength(2));
      expect(controller.currentDevice?.deviceId, 'CURRENT');
      expect(
        controller.devices.value.last.verification,
        SessionDeviceVerification.unverified,
      );
      expect(controller.errorMessage.value, isNull);
    },
  );

  test(
    'remote sign-out removes only the device after gateway success',
    () async {
      final gateway = _FakeSessionDeviceGateway()
        ..loaded = const <SessionDevice>[_current, _remote];
      final controller = SessionDeviceController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.signOutRemoteDevice('REMOTE'), isTrue);

      expect(gateway.signedOutDeviceIds, <String>['REMOTE']);
      expect(
        controller.devices.value.map((device) => device.deviceId),
        <String>['CURRENT'],
      );
      expect(controller.currentDevice?.deviceId, 'CURRENT');
    },
  );

  test(
    'current device cannot be remotely signed out through the device list',
    () async {
      final gateway = _FakeSessionDeviceGateway()
        ..loaded = const <SessionDevice>[_current, _remote];
      final controller = SessionDeviceController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.signOutRemoteDevice('CURRENT'), isFalse);

      expect(gateway.signedOutDeviceIds, isEmpty);
      expect(
        controller.errorMessage.value,
        'Sign out of this device from Kite account settings instead.',
      );
    },
  );

  test('gateway failures never expose token-like exception details', () async {
    final gateway = _FakeSessionDeviceGateway()
      ..loaded = const <SessionDevice>[_current, _remote];
    final controller = SessionDeviceController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    gateway.signOutError = StateError('access_token=remote-secret');
    expect(await controller.signOutRemoteDevice('REMOTE'), isFalse);

    expect(controller.devices.value, hasLength(2));
    expect(
      controller.errorMessage.value,
      'Kite could not sign out that device.',
    );
    expect(controller.errorMessage.value, isNot(contains('remote-secret')));
  });

  test('rejects duplicate or ambiguous current-device data', () async {
    final gateway = _FakeSessionDeviceGateway()
      ..loaded = const <SessionDevice>[
        _current,
        SessionDevice(
          deviceId: 'CURRENT',
          isCurrent: false,
          verification: SessionDeviceVerification.unknown,
        ),
      ];
    final controller = SessionDeviceController(gateway);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.devices.value, isEmpty);
    expect(
      controller.errorMessage.value,
      'Kite received an invalid device list.',
    );
  });
}
