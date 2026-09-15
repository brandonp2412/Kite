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
  int _accountGeneration = 0;

  final status = signal<EncryptionRecoveryStatus?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  bool get needsRecoveryAttention =>
      status.value?.needsRecoveryAttention ?? false;

  bool resetForAccountChange() {
    _accountGeneration += 1;
    status.value = null;
    isBusy.value = false;
    errorMessage.value = null;
    return true;
  }

  Future<bool> refresh() {
    return _run(
      _gateway.loadRecoveryStatus,
      failureMessage: 'Kite could not read encryption recovery status.',
    );
  }

  Future<bool> createEncryptedBackup() {
    return _run(
      _gateway.createEncryptedBackup,
      validateStatus: (next) => next.backupState == EncryptedBackupState.ready,
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
      validateStatus: (next) => next.backupState == EncryptedBackupState.ready,
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
      validateStatus: (next) => next.backupState == EncryptedBackupState.ready,
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
      validateStatus: (next) =>
          next.historicalRecoveryState == HistoricalRecoveryState.recovering ||
          next.historicalRecoveryState == HistoricalRecoveryState.complete,
      failureMessage: 'Kite could not recover encrypted message history.',
    );
  }

  Future<bool> _run(
    Future<EncryptionRecoveryStatus> Function() action, {
    bool Function(EncryptionRecoveryStatus status)? validateStatus,
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (generation != _accountGeneration) return false;
      if (validateStatus != null && !validateStatus(next)) {
        errorMessage.value = 'Kite received invalid encryption recovery state.';
        return false;
      }
      status.value = next;
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = failureMessage;
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
    }
  }

  void dispose() {
    status.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
