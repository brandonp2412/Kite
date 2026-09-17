import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class MatrixProductionRecoveryApi implements MatrixNativeRecoveryApi {
  const MatrixProductionRecoveryApi(this._runtime);

  final MatrixProductionRuntime _runtime;

  @override
  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus() async {
    return _status(
      await _runtime.encryptionRecoveryStatus(accountId: _activeAccountId()),
    );
  }

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackup(String secret) async {
    return _status(
      await _runtime.recoverEncryption(
        accountId: _activeAccountId(),
        secret: secret,
      ),
    );
  }

  @override
  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages() async {
    return _status(
      await _runtime.recoverEncryptedHistory(accountId: _activeAccountId()),
    );
  }

  String _activeAccountId() {
    final accountId = _runtime.activeAccountId.value;
    if (accountId == null) {
      throw StateError('Matrix recovery requires an active account');
    }
    return accountId;
  }

  static MatrixSdkRecoveryStatus _status(
    MatrixSdkEncryptionRecoveryStatus status,
  ) {
    final recovered =
        status.recoveryState == MatrixSdkEncryptionRecoveryState.enabled;
    final backupState = switch (status.recoveryState) {
      MatrixSdkEncryptionRecoveryState.enabled
          when status.backupExistsOnServer =>
        MatrixSdkBackupState.ready,
      MatrixSdkEncryptionRecoveryState.incomplete =>
        MatrixSdkBackupState.needsRecovery,
      MatrixSdkEncryptionRecoveryState.disabled
          when status.backupExistsOnServer =>
        MatrixSdkBackupState.needsRecovery,
      MatrixSdkEncryptionRecoveryState.disabled =>
        MatrixSdkBackupState.unavailable,
      MatrixSdkEncryptionRecoveryState.unknown
          when status.backupExistsOnServer =>
        MatrixSdkBackupState.needsRecovery,
      MatrixSdkEncryptionRecoveryState.unknown => MatrixSdkBackupState.unknown,
      MatrixSdkEncryptionRecoveryState.enabled =>
        MatrixSdkBackupState.unavailable,
    };
    final historyState = switch (status.backupState) {
      MatrixSdkEncryptionBackupState.downloading =>
        MatrixSdkHistoricalRecoveryState.recovering,
      MatrixSdkEncryptionBackupState.enabled when recovered =>
        MatrixSdkHistoricalRecoveryState.complete,
      _ when recovered && status.backupExistsOnServer =>
        MatrixSdkHistoricalRecoveryState.available,
      _ => MatrixSdkHistoricalRecoveryState.idle,
    };
    return MatrixSdkRecoveryStatus(
      backupState: backupState,
      historicalRecoveryState: historyState,
      hasUnverifiedSessions: false,
    );
  }
}
