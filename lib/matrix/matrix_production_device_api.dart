import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class MatrixProductionDeviceApi implements MatrixNativeDeviceApi {
  const MatrixProductionDeviceApi(this._runtime);

  final MatrixProductionRuntime _runtime;

  @override
  Future<List<MatrixSdkDeviceDescriptor>> loadDevices() async {
    final devices = await _runtime.loadDevices(accountId: _activeAccountId());
    return List<MatrixSdkDeviceDescriptor>.unmodifiable(
      devices.map(
        (device) => MatrixSdkDeviceDescriptor(
          deviceId: device.deviceId,
          isCurrent: device.isCurrent,
          verification: switch (device.isVerified) {
            true => MatrixSdkDeviceVerification.verified,
            false => MatrixSdkDeviceVerification.unverified,
            null => MatrixSdkDeviceVerification.unknown,
          },
          displayName: device.displayName,
          lastSeenAt: device.lastSeenAt,
        ),
      ),
    );
  }

  @override
  Future<void> signOutDevice(String deviceId, {required String password}) =>
      _runtime.signOutDevice(
        accountId: _activeAccountId(),
        deviceId: deviceId,
        password: password,
      );

  String _activeAccountId() {
    final accountId = _runtime.activeAccountId.value;
    if (accountId == null) {
      throw StateError('Matrix device listing requires an active account');
    }
    return accountId;
  }
}
