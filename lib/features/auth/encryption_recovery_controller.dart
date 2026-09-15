import 'package:signals/signals.dart';

enum EncryptedBackupState { unknown, unavailable, ready, needsRecovery }

enum HistoricalRecoveryState { idle, available, recovering, complete }

final class EncryptionRecoveryStatus {
  const EncryptionRecoveryStatus({
    required this.backupState,
    required this.historicalRecoveryState,
    required this.hasUnverifiedSessions,
  });

  final EncryptedBackupState backupState;
  final HistoricalRecoveryState historicalRecoveryState;
  final bool hasUnverifiedSessions;

  bool get needsRecoveryAttention =>
      backupState == EncryptedBackupState.needsRecovery ||
      hasUnverifiedSessions;

  @override
  String toString() =>
      'EncryptionRecoveryStatus('
      'backupState: $backupState, '
      'historicalRecoveryState: $historicalRecoveryState, '
      'hasUnverifiedSessions: $hasUnverifiedSessions'
      ')';
}

abstract interface class EncryptionRecoveryGateway {
  /// Reads recovery state from the audited Matrix SDK boundary.
  Future<EncryptionRecoveryStatus> loadRecoveryStatus();

  /// Creates/enables an SDK-managed encrypted backup.
  Future<EncryptionRecoveryStatus> createEncryptedBackup();

  /// Supplies an opaque recovery key to the SDK. Kite must never derive,
  /// persist, or log this secret.
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(String recoveryKey);

  /// Supplies an opaque recovery passphrase to the SDK. Kite must never
  /// derive, persist, or log this secret.
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(String passphrase);

  /// Asks the SDK to retry recovery of historical encrypted events.
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages();
}

final class EncryptionRecoveryController {
  EncryptionRecoveryController(this._gateway);

  final EncryptionRecoveryGateway _gateway;

  final status = signal<EncryptionRecoveryStatus?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  bool get needsRecoveryAttention =>
      status.value?.needsRecoveryAttention ?? false;

  Future<bool> refresh() {
    return _run(
      _gateway.loadRecoveryStatus,
      failureMessage: 'Kite could not read encryption recovery status.',
    );
  }

  Future<bool> createEncryptedBackup() {
    return _run(
      _gateway.createEncryptedBackup,
      failureMessage: 'Kite could not enable encrypted backup.',
    );
  }

  Future<bool> restoreWithRecoveryKey(String recoveryKey) {
    final secret = recoveryKey.trim();
    if (secret.isEmpty) {
      errorMessage.value = 'Enter your recovery key.';
      return Future<bool>.value(false);
    }
    return _run(
      () => _gateway.restoreWithRecoveryKey(secret),
      failureMessage: 'Kite could not restore encrypted backup.',
    );
  }

  Future<bool> restoreWithPassphrase(String passphrase) {
    if (passphrase.isEmpty) {
      errorMessage.value = 'Enter your recovery passphrase.';
      return Future<bool>.value(false);
    }
    return _run(
      () => _gateway.restoreWithPassphrase(passphrase),
      failureMessage: 'Kite could not restore encrypted backup.',
    );
  }

  Future<bool> recoverHistoricalMessages() {
    if (status.value?.historicalRecoveryState !=
        HistoricalRecoveryState.available) {
      errorMessage.value = 'Encrypted history recovery is not available.';
      return Future<bool>.value(false);
    }
    return _run(
      _gateway.recoverHistoricalMessages,
      failureMessage: 'Kite could not recover encrypted message history.',
    );
  }

  Future<bool> _run(
    Future<EncryptionRecoveryStatus> Function() action, {
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      status.value = await action();
      return true;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  void dispose() {
    status.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
