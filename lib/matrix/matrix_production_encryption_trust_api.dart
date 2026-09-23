import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class MatrixProductionEncryptionTrustApi
    implements MatrixNativeEncryptionTrustApi {
  const MatrixProductionEncryptionTrustApi(this._runtime);

  final MatrixProductionRuntime _runtime;

  @override
  Future<MatrixSdkCrossSigningTrust> loadCrossSigningTrust() async {
    final trust = await _runtime.loadCrossSigningTrust(
      accountId: _activeAccountId(),
    );
    return switch (trust) {
      MatrixSdkCrossSigningTrustState.unknown =>
        MatrixSdkCrossSigningTrust.unknown,
      MatrixSdkCrossSigningTrustState.unverified =>
        MatrixSdkCrossSigningTrust.unverified,
      MatrixSdkCrossSigningTrustState.verified =>
        MatrixSdkCrossSigningTrust.verified,
    };
  }

  @override
  Future<MatrixSdkRoomEncryptionTrust> loadRoomEncryptionTrust(
    String roomId,
  ) async {
    final trust = await _runtime.loadRoomEncryptionTrust(
      accountId: _activeAccountId(),
      roomId: roomId,
    );
    return MatrixSdkRoomEncryptionTrust(
      roomId: trust.roomId,
      isEncrypted: trust.isEncrypted,
      trustState: !trust.isEncrypted
          ? MatrixSdkEncryptionTrustState.unknown
          : trust.allDevicesVerified == true
          ? MatrixSdkEncryptionTrustState.verified
          : trust.allDevicesVerified == false
          ? MatrixSdkEncryptionTrustState.unverifiedDevice
          : MatrixSdkEncryptionTrustState.unknown,
      historySharingSupported: false,
      historySharingEnabled: false,
    );
  }

  String _activeAccountId() {
    final accountId = _runtime.activeAccountId.value;
    if (accountId == null) {
      throw StateError(
        'Matrix encryption trust lookup requires an active account',
      );
    }
    return accountId;
  }
}
