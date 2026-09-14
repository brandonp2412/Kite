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

  Future<void> load() async {
    if (isLoading.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    try {
      final loaded = await _gateway.loadDevices();
      if (_isValidDeviceList(loaded) == false) {
        errorMessage.value = 'Kite received an invalid device list.';
        return;
      }
      devices.value = List<SessionDevice>.unmodifiable(loaded);
    } catch (_) {
      errorMessage.value = 'Kite could not load your signed-in devices.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> signOutRemoteDevice(String deviceId) async {
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
    if (signingOutDeviceIds.value.contains(deviceId)) return false;

    errorMessage.value = null;
    signingOutDeviceIds.value = <String>{
      ...signingOutDeviceIds.value,
      deviceId,
    };
    try {
      await _gateway.signOutDevice(deviceId);
      devices.value = List<SessionDevice>.unmodifiable(
        devices.value.where(
          (candidate) => candidate.deviceId == deviceId ? false : true,
        ),
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not sign out that device.';
      return false;
    } finally {
      final remaining = <String>{...signingOutDeviceIds.value}
        ..remove(deviceId);
      signingOutDeviceIds.value = remaining;
    }
  }

  SessionDevice? _findDevice(String deviceId) {
    for (final device in devices.value) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  bool _isValidDeviceList(List<SessionDevice> loaded) {
    final ids = <String>{};
    var currentCount = 0;
    for (final device in loaded) {
      if (device.deviceId.trim().isEmpty) return false;
      if (ids.add(device.deviceId) == false) return false;
      if (device.isCurrent) currentCount += 1;
      if (currentCount > 1) return false;
    }
    return true;
  }

  void dispose() {
    devices.dispose();
    isLoading.dispose();
    signingOutDeviceIds.dispose();
    errorMessage.dispose();
  }
}
