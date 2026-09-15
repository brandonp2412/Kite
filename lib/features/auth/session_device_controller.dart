import 'package:signals/signals.dart';

enum SessionDeviceVerification { verified, unverified, unknown }

final class SessionDevice {
  const SessionDevice({
    required this.deviceId,
    required this.isCurrent,
    required this.verification,
    this.displayName,
    this.lastSeenAt,
  });

  final String deviceId;
  final bool isCurrent;
  final SessionDeviceVerification verification;
  final String? displayName;
  final DateTime? lastSeenAt;
}

abstract interface class SessionDeviceGateway {
  Future<List<SessionDevice>> loadDevices();

  Future<void> signOutDevice(String deviceId);
}

final class SessionDeviceController {
  SessionDeviceController(this._gateway);

  final SessionDeviceGateway _gateway;
  int _accountGeneration = 0;

  final devices = signal<List<SessionDevice>>(const <SessionDevice>[]);
  final isLoading = signal(false);
  final signingOutDeviceIds = signal<Set<String>>(const <String>{});
  final errorMessage = signal<String?>(null);

  SessionDevice? get currentDevice {
    for (final device in devices.value) {
      if (device.isCurrent) return device;
    }
    return null;
  }

  Future<void> load({String? expectedCurrentDeviceId}) async {
    if (isLoading.value || signingOutDeviceIds.value.isNotEmpty) return;
    final expectedDeviceId = expectedCurrentDeviceId?.trim();
    if (expectedCurrentDeviceId != null &&
        (expectedDeviceId!.isEmpty ||
            expectedDeviceId != expectedCurrentDeviceId)) {
      devices.value = const <SessionDevice>[];
      errorMessage.value = 'Kite received an invalid current device identity.';
      return;
    }

    final generation = _accountGeneration;
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final loaded = await _gateway.loadDevices();
      if (generation != _accountGeneration) return;
      if (_isValidDeviceList(
            loaded,
            expectedCurrentDeviceId: expectedDeviceId,
          ) ==
          false) {
        devices.value = const <SessionDevice>[];
        errorMessage.value = expectedDeviceId == null
            ? 'Kite received an invalid device list.'
            : 'Kite could not confirm the current Matrix device.';
        return;
      }
      devices.value = List<SessionDevice>.unmodifiable(loaded);
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not load your signed-in devices.';
      }
    } finally {
      if (generation == _accountGeneration) {
        isLoading.value = false;
      }
    }
  }

  bool resetForAccountChange() {
    _accountGeneration += 1;
    devices.value = const <SessionDevice>[];
    isLoading.value = false;
    signingOutDeviceIds.value = const <String>{};
    errorMessage.value = null;
    return true;
  }

  Future<bool> signOutRemoteDevice(String deviceId) async {
    if (isLoading.value || signingOutDeviceIds.value.isNotEmpty) return false;
    final device = _findDevice(deviceId);
    if (device == null) {
      errorMessage.value = 'That signed-in device is no longer available.';
      return false;
    }
    if (device.isCurrent) {
      errorMessage.value =
          'Sign out of this device from Kite account settings instead.';
      return false;
    }
    final generation = _accountGeneration;
    errorMessage.value = null;
    signingOutDeviceIds.value = <String>{
      ...signingOutDeviceIds.value,
      deviceId,
    };
    try {
      await _gateway.signOutDevice(deviceId);
      if (generation != _accountGeneration) return false;
      devices.value = List<SessionDevice>.unmodifiable(
        devices.value.where(
          (candidate) => candidate.deviceId == deviceId ? false : true,
        ),
      );
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not sign out that device.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        final remaining = <String>{...signingOutDeviceIds.value}
          ..remove(deviceId);
        signingOutDeviceIds.value = remaining;
      }
    }
  }

  SessionDevice? _findDevice(String deviceId) {
    for (final device in devices.value) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  bool _isValidDeviceList(
    List<SessionDevice> loaded, {
    String? expectedCurrentDeviceId,
  }) {
    final ids = <String>{};
    SessionDevice? currentDevice;
    for (final device in loaded) {
      final deviceId = device.deviceId.trim();
      if (deviceId.isEmpty || deviceId != device.deviceId) return false;
      if (ids.add(device.deviceId) == false) return false;
      if (device.isCurrent) {
        if (currentDevice != null) return false;
        currentDevice = device;
      }
    }
    if (loaded.isEmpty) return expectedCurrentDeviceId == null;
    if (currentDevice == null) return false;
    return expectedCurrentDeviceId == null ||
        currentDevice.deviceId == expectedCurrentDeviceId;
  }

  void dispose() {
    devices.dispose();
    isLoading.dispose();
    signingOutDeviceIds.dispose();
    errorMessage.dispose();
  }
}
