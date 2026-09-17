import 'package:signals/signals.dart';

enum EncryptedBackupState { unknown, unavailable, ready, needsRecovery }

enum HistoricalRecoveryState { idle, available, recovering, complete }

final class RoomKeyBackupImportResult {
  const RoomKeyBackupImportResult({
    required this.importedCount,
    required this.totalCount,
  });

  final int importedCount;
  final int totalCount;
}

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

abstract interface class RoomKeyBackupImportGateway {
  /// Imports an Element-style encrypted room-key export into the SDK crypto
  /// store. Neither the backup contents nor its passphrase may be retained.
  Future<RoomKeyBackupImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  });
}

final class EncryptionRecoveryController {
  EncryptionRecoveryController(this._gateway);

  final EncryptionRecoveryGateway _gateway;
  int _accountGeneration = 0;

  final status = signal<EncryptionRecoveryStatus?>(null);
  final roomKeyImportResult = signal<RoomKeyBackupImportResult?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  bool get needsRecoveryAttention =>
      status.value?.needsRecoveryAttention ?? false;

  bool resetForAccountChange() {
    _accountGeneration += 1;
    status.value = null;
    roomKeyImportResult.value = null;
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

  Future<bool> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) async {
    if (path.trim().isEmpty) {
      errorMessage.value = 'Choose your Element room-key backup file.';
      return false;
    }
    if (passphrase.isEmpty) {
      errorMessage.value = 'Enter the passphrase for that room-key backup.';
      return false;
    }
    if (isBusy.value) return false;

    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    roomKeyImportResult.value = null;
    final importer = _gateway;
    if (importer is! RoomKeyBackupImportGateway) {
      isBusy.value = false;
      errorMessage.value = 'Room-key backup import is not available.';
      return false;
    }
    try {
      final result = await (importer as RoomKeyBackupImportGateway)
          .importRoomKeyBackup(path: path, passphrase: passphrase);
      if (generation != _accountGeneration) return false;
      roomKeyImportResult.value = result;
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not decrypt that room-key backup. Check its export passphrase.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
    }
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
    roomKeyImportResult.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
