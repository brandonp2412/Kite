import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_recovery_screen.dart';
import 'package:kite/l10n/generated/app_localizations.dart';

final class _FakeRecoveryGateway implements EncryptionRecoveryGateway {
  EncryptionRecoveryStatus status = const EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );
  String? recoveryKey;
  String? passphrase;
  Completer<EncryptionRecoveryStatus>? deferredRecoveryKey;
  Completer<EncryptionRecoveryStatus>? deferredStatus;
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
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async {
    final deferred = deferredStatus;
    if (deferred != null) return deferred.future;
    return status;
  }

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

Widget _app(
  EncryptionRecoveryController controller, {
  bool loadOnInit = false,
  Locale? locale,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: EncryptionRecoveryScreen(
      controller: controller,
      loadOnInit: loadOnInit,
    ),
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
    controller.status.value = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.unknown,
      historicalRecoveryState: HistoricalRecoveryState.idle,
      hasUnverifiedSessions: false,
    );

    await tester.pumpWidget(_app(controller));

    expect(find.text('Recovery status is not available yet'), findsOneWidget);
    expect(
      find.text(
        'Matrix has not reported enough backup state to determine whether recovery is configured.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Some signed-in sessions are not verified.'),
      findsNothing,
    );
  });

  testWidgets('status loading never disables recovery key input', (
    tester,
  ) async {
    final gateway = _FakeRecoveryGateway()
      ..deferredStatus = Completer<EncryptionRecoveryStatus>();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, loadOnInit: true));
    await tester.pump();

    expect(controller.isRefreshingStatus.value, isTrue);
    expect(controller.isBusy.value, isFalse);
    final recoveryKey = tester.widget<TextField>(
      find.byKey(const Key('recovery-key-field')),
    );
    expect(recoveryKey.enabled, isTrue);

    gateway.deferredStatus!.complete(gateway.status);
    await tester.pumpAndSettle();
    expect(controller.isRefreshingStatus.value, isFalse);
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
      controller.activeOperation.value,
      EncryptionRecoveryOperation.restoreBackup,
    );
    expect(
      find.byKey(const Key('encryption-recovery-progress')),
      findsOneWidget,
    );
    expect(
      find.text('Restoring encrypted messages and downloading room keys…'),
      findsOneWidget,
    );
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
    expect(controller.activeOperation.value, isNull);
    expect(find.byKey(const Key('encryption-recovery-progress')), findsNothing);
    expect(
      find.byKey(const Key('encryption-recovery-success')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Encrypted messages restored. Recent chat history is reloading.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('room-key import success formats counts in the active locale', (
    tester,
  ) async {
    final gateway = _FakeRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    controller.roomKeyImportResult.value = const RoomKeyBackupImportResult(
      importedCount: 1234,
      totalCount: 5678,
    );
    controller.successMessage.value =
        'Room keys imported. Recent chat history is reloading.';

    await tester.pumpWidget(_app(controller, locale: const Locale('de')));
    await tester.pump();

    expect(
      find.text(
        'Imported 1.234 of 5.678 room keys. Recent chat history is reloading.',
      ),
      findsOneWidget,
    );
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
