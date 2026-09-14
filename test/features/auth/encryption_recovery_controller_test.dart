import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';

final class _FakeEncryptionRecoveryGateway
    implements EncryptionRecoveryGateway {
  EncryptionRecoveryStatus current = const EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );
  Object? failure;
  String? recoveryKey;
  String? passphrase;
  int createCalls = 0;
  int historicalRecoveryCalls = 0;

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async {
    if (failure case final error?) throw error;
    createCalls += 1;
    current = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return current;
  }

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async {
    if (failure case final error?) throw error;
    return current;
  }

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async {
    if (failure case final error?) throw error;
    historicalRecoveryCalls += 1;
    current = EncryptionRecoveryStatus(
      backupState: current.backupState,
      historicalRecoveryState: HistoricalRecoveryState.complete,
      hasUnverifiedSessions: current.hasUnverifiedSessions,
    );
    return current;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async {
    if (failure case final error?) throw error;
    this.passphrase = passphrase;
    current = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return current;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async {
    if (failure case final error?) throw error;
    this.recoveryKey = recoveryKey;
    current = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return current;
  }
}

void main() {
  test(
    'recovery status exposes attention state without holding secrets',
    () async {
      final gateway = _FakeEncryptionRecoveryGateway();
      final controller = EncryptionRecoveryController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.refresh(), isTrue);
      expect(controller.needsRecoveryAttention, isTrue);
      expect(
        controller.status.value?.historicalRecoveryState,
        HistoricalRecoveryState.available,
      );
      expect(controller.status.value.toString(), isNot(contains('secret')));
    },
  );

  test('backup creation is delegated to the Matrix SDK boundary', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.createEncryptedBackup(), isTrue);
    expect(gateway.createCalls, 1);
    expect(controller.status.value?.backupState, EncryptedBackupState.ready);
    expect(controller.needsRecoveryAttention, isFalse);
  });

  test('recovery key and passphrase are transient gateway inputs', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.restoreWithRecoveryKey('  OPAQUE-RECOVERY-KEY  '),
      isTrue,
    );
    expect(gateway.recoveryKey, 'OPAQUE-RECOVERY-KEY');
    expect(controller.status.value.toString(), isNot(contains('OPAQUE')));

    expect(
      await controller.restoreWithPassphrase('correct horse battery staple'),
      isTrue,
    );
    expect(gateway.passphrase, 'correct horse battery staple');
    expect(
      controller.status.value.toString(),
      isNot(contains('correct horse')),
    );
  });

  test('empty recovery secrets are rejected before the SDK boundary', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.restoreWithRecoveryKey('   '), isFalse);
    expect(controller.errorMessage.value, 'Enter your recovery key.');
    expect(gateway.recoveryKey, isNull);

    expect(await controller.restoreWithPassphrase(''), isFalse);
    expect(controller.errorMessage.value, 'Enter your recovery passphrase.');
    expect(gateway.passphrase, isNull);
  });

  test('historical recovery is an SDK-owned operation', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.recoverHistoricalMessages(), isTrue);
    expect(gateway.historicalRecoveryCalls, 1);
    expect(
      controller.status.value?.historicalRecoveryState,
      HistoricalRecoveryState.complete,
    );
  });

  test('gateway failures expose only fixed public errors', () async {
    final gateway = _FakeEncryptionRecoveryGateway()
      ..failure = StateError(
        'access_token=token recovery_key=RECOVERY passphrase=SECRET',
      );
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.restoreWithRecoveryKey('RECOVERY'), isFalse);
    expect(
      controller.errorMessage.value,
      'Kite could not restore encrypted backup.',
    );
    expect(controller.errorMessage.value, isNot(contains('RECOVERY')));
    expect(controller.errorMessage.value, isNot(contains('SECRET')));
    expect(controller.errorMessage.value, isNot(contains('access_token')));
  });
}
