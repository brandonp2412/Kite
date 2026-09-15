import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_recovery_screen.dart';

final class _DeferredRecoveryGateway implements EncryptionRecoveryGateway {
  final create = Completer<EncryptionRecoveryStatus>();

  static const initial = EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() => create.future;

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async => initial;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async => initial;

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async => initial;

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async => initial;
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('recovery busy state keeps reserved geometry stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredRecoveryGateway();
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: EncryptionRecoveryScreen(
          controller: controller,
          loadOnInit: false,
        ),
      ),
    );

    final list = find.byKey(const Key('encryption-recovery-list'));
    final summary = find.byKey(const Key('encryption-recovery-summary'));
    final statusSlot = find.byKey(const Key('encryption-recovery-status-slot'));
    final initialList = _rectOf(tester, list);
    final initialSummary = _rectOf(tester, summary);
    final initialStatusSlot = _rectOf(tester, statusSlot);

    await tester.tap(find.byKey(const Key('create-encrypted-backup')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, summary), initialSummary);
      expect(_rectOf(tester, statusSlot), initialStatusSlot);
      expect(tester.takeException(), isNull);
    }

    gateway.create.complete(
      const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.ready,
        historicalRecoveryState: HistoricalRecoveryState.available,
        hasUnverifiedSessions: false,
      ),
    );
    await tester.pump();
    expect(_rectOf(tester, summary), initialSummary);
    expect(_rectOf(tester, statusSlot), initialStatusSlot);
  });
}
