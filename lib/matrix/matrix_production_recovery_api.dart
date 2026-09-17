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
  Future<MatrixSdkRecoveryStatus> createEncryptedBackup() async {
    return _status(
      await _runtime.createEncryptedBackup(accountId: _activeAccountId()),
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
    final status = _status(
      await _runtime.recoverEncryptedHistory(accountId: _activeAccountId()),
    );
    return MatrixSdkRecoveryStatus(
      backupState: status.backupState,
      historicalRecoveryState: MatrixSdkHistoricalRecoveryState.complete,
      hasUnverifiedSessions: status.hasUnverifiedSessions,
    );
  }

  @override
  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) {
    return _runtime.importRoomKeyBackup(
      accountId: _activeAccountId(),
      path: path,
      passphrase: passphrase,
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
    final backupState = switch (status.backupState) {
      MatrixSdkEncryptionBackupState.enabled => MatrixSdkBackupState.ready,
      _
          when status.recoveryState ==
              MatrixSdkEncryptionRecoveryState.incomplete =>
        MatrixSdkBackupState.needsRecovery,
      _
          when status.backupExistsOnServer &&
              status.recoveryState !=
                  MatrixSdkEncryptionRecoveryState.enabled =>
        MatrixSdkBackupState.needsRecovery,
      _ when status.backupExistsOnServer => MatrixSdkBackupState.ready,
      _ when status.recoveryState == MatrixSdkEncryptionRecoveryState.unknown =>
        MatrixSdkBackupState.unknown,
      _ => MatrixSdkBackupState.unavailable,
    };
    final historyState = switch (status.backupState) {
      MatrixSdkEncryptionBackupState.downloading =>
        MatrixSdkHistoricalRecoveryState.recovering,
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
