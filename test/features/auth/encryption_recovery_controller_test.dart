import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';

final class _FakeEncryptionRecoveryGateway
    implements EncryptionRecoveryGateway, RoomKeyBackupImportGateway {
  EncryptionRecoveryStatus current = const EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );
  Object? failure;
  EncryptionRecoveryStatus? overrideResult;
  String? recoveryKey;
  String? passphrase;
  String? importedPath;
  String? importedPassphrase;
  int createCalls = 0;
  int historicalRecoveryCalls = 0;
  Completer<EncryptionRecoveryStatus>? deferredStatus;

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async {
    if (failure case final error?) throw error;
    createCalls += 1;
    current = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return overrideResult ?? current;
  }

  @override
  Future<RoomKeyBackupImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) async {
    if (failure case final error?) throw error;
    importedPath = path;
    importedPassphrase = passphrase;
    return const RoomKeyBackupImportResult(importedCount: 185, totalCount: 185);
  }

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async {
    if (failure case final error?) throw error;
    final deferred = deferredStatus;
    if (deferred != null) return deferred.future;
    return overrideResult ?? current;
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
    return overrideResult ?? current;
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
    return overrideResult ?? current;
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
    return overrideResult ?? current;
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

  test('account change reset clears recovery state', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.refresh(), isTrue);
    expect(controller.status.value, isNotNull);

    expect(controller.resetForAccountChange(), isTrue);
    expect(controller.status.value, isNull);
    expect(controller.errorMessage.value, isNull);
    expect(controller.needsRecoveryAttention, isFalse);
  });

  test('account reset invalidates an in-flight recovery refresh', () async {
    final deferred = Completer<EncryptionRecoveryStatus>();
    final gateway = _FakeEncryptionRecoveryGateway()..deferredStatus = deferred;
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBusy.value, isTrue);

    expect(controller.resetForAccountChange(), isTrue);
    expect(controller.isBusy.value, isFalse);
    deferred.complete(gateway.current);
    expect(await refresh, isFalse);

    expect(controller.status.value, isNull);
    expect(controller.errorMessage.value, isNull);
  });

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

  test(
    'Element room-key backup is imported with its export passphrase',
    () async {
      final gateway = _FakeEncryptionRecoveryGateway();
      final controller = EncryptionRecoveryController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.importRoomKeyBackup(
          path: '/tmp/element-e2e-keys.txt',
          passphrase: 'export-passphrase',
        ),
        isTrue,
      );
      expect(gateway.importedPath, '/tmp/element-e2e-keys.txt');
      expect(gateway.importedPassphrase, 'export-passphrase');
      expect(controller.roomKeyImportResult.value?.importedCount, 185);
      expect(controller.roomKeyImportResult.value?.totalCount, 185);
    },
  );

  test('room-key backup import validates file and passphrase', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.importRoomKeyBackup(path: '', passphrase: 'secret'),
      isFalse,
    );
    expect(
      controller.errorMessage.value,
      'Choose your Element room-key backup file.',
    );

    expect(
      await controller.importRoomKeyBackup(
        path: '/tmp/backup.txt',
        passphrase: '',
      ),
      isFalse,
    );
    expect(
      controller.errorMessage.value,
      'Enter the passphrase for that room-key backup.',
    );
  });

  test('historical recovery is an SDK-owned operation', () async {
    final gateway = _FakeEncryptionRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    expect(await controller.refresh(), isTrue);

    expect(await controller.recoverHistoricalMessages(), isTrue);
    expect(gateway.historicalRecoveryCalls, 1);
    expect(
      controller.status.value?.historicalRecoveryState,
      HistoricalRecoveryState.complete,
    );
  });

  test('historical recovery requires SDK-advertised availability', () async {
    final gateway = _FakeEncryptionRecoveryGateway()
      ..current = const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.ready,
        historicalRecoveryState: HistoricalRecoveryState.idle,
        hasUnverifiedSessions: false,
      );
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    expect(await controller.refresh(), isTrue);

    expect(await controller.recoverHistoricalMessages(), isFalse);
    expect(gateway.historicalRecoveryCalls, 0);
    expect(
      controller.errorMessage.value,
      'Encrypted history recovery is not available.',
    );
  });

  test(
    'successful operations reject contradictory SDK recovery state',
    () async {
      final gateway = _FakeEncryptionRecoveryGateway();
      final controller = EncryptionRecoveryController(gateway);
      addTearDown(controller.dispose);
      expect(await controller.refresh(), isTrue);
      final previous = controller.status.value;

      gateway.overrideResult = const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.needsRecovery,
        historicalRecoveryState: HistoricalRecoveryState.available,
        hasUnverifiedSessions: false,
      );
      expect(await controller.createEncryptedBackup(), isFalse);
      expect(controller.status.value, same(previous));
      expect(
        controller.errorMessage.value,
        'Kite received invalid encryption recovery state.',
      );

      gateway.overrideResult = const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.ready,
        historicalRecoveryState: HistoricalRecoveryState.available,
        hasUnverifiedSessions: false,
      );
      expect(await controller.recoverHistoricalMessages(), isFalse);
      expect(controller.status.value, same(previous));
    },
  );

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

    expect(
      await controller.importRoomKeyBackup(
        path: '/tmp/room-keys.txt',
        passphrase: 'SECRET',
      ),
      isFalse,
    );
    expect(
      controller.errorMessage.value,
      'Kite could not decrypt that room-key backup. Check its export passphrase.',
    );
    expect(controller.errorMessage.value, isNot(contains('SECRET')));
  });
}
