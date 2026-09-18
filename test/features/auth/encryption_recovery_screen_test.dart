import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_recovery_screen.dart';

final class _FakeRecoveryGateway implements EncryptionRecoveryGateway {
  EncryptionRecoveryStatus status = const EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );
  String? recoveryKey;
  String? passphrase;
  Completer<EncryptionRecoveryStatus>? deferredRecoveryKey;
  int createCalls = 0;
  int historyCalls = 0;

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async {
    createCalls += 1;
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async => status;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async {
    historyCalls += 1;
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.complete,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async {
    this.passphrase = passphrase;
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async {
    this.recoveryKey = recoveryKey;
    final deferred = deferredRecoveryKey;
    if (deferred != null) return deferred.future;
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }
}

Widget _app(EncryptionRecoveryController controller) {
  return MaterialApp(
    home: EncryptionRecoveryScreen(controller: controller, loadOnInit: false),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _expandOtherRecoveryMethods(WidgetTester tester) async {
  final otherMethods = find.byKey(
    const Key('encryption-recovery-other-methods'),
  );
  await _scrollTo(tester, otherMethods);
  await tester.tap(otherMethods);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown recovery state never claims sessions are verified', (
    tester,
  ) async {
    final controller = EncryptionRecoveryController(_FakeRecoveryGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    expect(find.text('Check your recovery setup'), findsOneWidget);
    expect(
      find.text('Kite is checking the Matrix backup and session state.'),
      findsOneWidget,
    );
    expect(
      find.text('Some signed-in sessions are not verified.'),
      findsNothing,
    );
  });

  testWidgets('renders SDK recovery state and delegates recovery actions', (
    tester,
  ) async {
    final gateway = _FakeRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(_app(controller));

    expect(find.text('Recovery needs attention'), findsOneWidget);
    expect(
      find.text(
        'Restore your encryption keys to read older encrypted messages.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Some signed-in sessions are not verified.'),
      findsOneWidget,
    );

    final createBackup = find.byKey(const Key('create-encrypted-backup'));
    await _scrollTo(tester, createBackup);
    await tester.tap(createBackup);
    await tester.pump();
    expect(gateway.createCalls, 1);
    expect(find.text('Recovery is set up'), findsOneWidget);
    expect(find.text('Encrypted backup is ready'), findsOneWidget);

    final recoverHistory = find.byKey(const Key('recover-history'));
    await _scrollTo(tester, recoverHistory);
    await tester.tap(recoverHistory);
    await tester.pump();
    expect(gateway.historyCalls, 1);
    expect(
      controller.status.value?.historicalRecoveryState,
      HistoricalRecoveryState.complete,
    );
  });

  testWidgets('recovery key leaves the text field before SDK completion', (
    tester,
  ) async {
    final gateway = _FakeRecoveryGateway()
      ..deferredRecoveryKey = Completer<EncryptionRecoveryStatus>();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(_app(controller));

    await _expandOtherRecoveryMethods(tester);
    final passphraseField = find.byKey(const Key('recovery-passphrase-field'));
    await _scrollTo(tester, passphraseField);
    await tester.enterText(passphraseField, 'unused secret');
    final recoveryKeyField = find.byKey(const Key('recovery-key-field'));
    await _scrollTo(tester, recoveryKeyField);
    await tester.enterText(recoveryKeyField, 'TRANSIENT-RECOVERY-KEY');
    final restoreRecoveryKey = find.byKey(const Key('restore-recovery-key'));
    await _scrollTo(tester, restoreRecoveryKey);
    await tester.tap(restoreRecoveryKey);
    await tester.pump();

    expect(gateway.recoveryKey, 'TRANSIENT-RECOVERY-KEY');
    expect(controller.isBusy.value, isTrue);
    expect(
      tester.widget<TextField>(recoveryKeyField).controller?.text,
      isEmpty,
    );
    await _scrollTo(tester, passphraseField);
    expect(tester.widget<TextField>(passphraseField).controller?.text, isEmpty);
    expect(find.textContaining('TRANSIENT-RECOVERY-KEY'), findsNothing);
    expect(find.textContaining('unused secret'), findsNothing);

    gateway.deferredRecoveryKey!.complete(
      const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.ready,
        historicalRecoveryState: HistoricalRecoveryState.available,
        hasUnverifiedSessions: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isBusy.value, isFalse);
  });

  testWidgets(
    'recovery secrets are cleared from text fields after submission',
    (tester) async {
      final gateway = _FakeRecoveryGateway();
      final controller = EncryptionRecoveryController(gateway);
      addTearDown(controller.dispose);
      await controller.refresh();

      await tester.pumpWidget(_app(controller));

      await tester.enterText(
        find.byKey(const Key('recovery-key-field')),
        '  OPAQUE-KEY  ',
      );
      await tester.tap(find.byKey(const Key('restore-recovery-key')));
      await tester.pump();

      expect(gateway.recoveryKey, 'OPAQUE-KEY');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('recovery-key-field')))
            .controller
            ?.text,
        isEmpty,
      );
      expect(find.textContaining('OPAQUE-KEY'), findsNothing);

      await _expandOtherRecoveryMethods(tester);
      final passphraseField = find.byKey(
        const Key('recovery-passphrase-field'),
      );
      await _scrollTo(tester, passphraseField);
      await tester.enterText(passphraseField, 'correct horse battery staple');
      final restorePassphrase = find.byKey(const Key('restore-passphrase'));
      await _scrollTo(tester, restorePassphrase);
      await tester.tap(restorePassphrase);
      await tester.pump();

      expect(gateway.passphrase, 'correct horse battery staple');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('recovery-passphrase-field')),
            )
            .controller
            ?.text,
        isEmpty,
      );
      expect(find.textContaining('correct horse'), findsNothing);
    },
  );

  testWidgets('empty recovery input stays inside fixed public error copy', (
    tester,
  ) async {
    final gateway = _FakeRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('restore-recovery-key')));
    await tester.pump();

    final error = find.text('Enter your recovery key.');
    await _scrollTo(tester, error);
    expect(error, findsOneWidget);
    expect(gateway.recoveryKey, isNull);
  });
}
