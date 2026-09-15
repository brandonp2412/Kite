import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/settings/privacy_security_settings_screen.dart';

final class _DeferredVerificationGateway implements DeviceVerificationGateway {
  final trust = Completer<CrossSigningTrustState>();

  @override
  Future<void> cancelVerification(String transactionId) async {}

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() => trust.future;

  @override
  Future<DeviceVerificationSession> startQrVerification() async =>
      throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> startSasVerification() async =>
      throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async => throw UnimplementedError();
}

final class _DeferredRecoveryGateway implements EncryptionRecoveryGateway {
  final status = Completer<EncryptionRecoveryStatus>();

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() => status.future;

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() => status.future;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() => status.future;

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(String passphrase) =>
      status.future;

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(String recoveryKey) =>
      status.future;
}

final class _DeferredSessionGateway implements SessionDeviceGateway {
  final devices = Completer<List<SessionDevice>>();

  @override
  Future<List<SessionDevice>> loadDevices() => devices.future;

  @override
  Future<void> signOutDevice(String deviceId) async {}
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets(
    'security status loading keeps settings geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final verificationGateway = _DeferredVerificationGateway();
      final recoveryGateway = _DeferredRecoveryGateway();
      final sessionGateway = _DeferredSessionGateway();
      final verification = DeviceVerificationController(verificationGateway);
      final recovery = EncryptionRecoveryController(recoveryGateway);
      final sessions = SessionDeviceController(sessionGateway);
      addTearDown(verification.dispose);
      addTearDown(recovery.dispose);
      addTearDown(sessions.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacySecuritySettingsScreen(
            verificationController: verification,
            recoveryController: recovery,
            sessionDeviceController: sessions,
            onOpenVerification: () {},
            onOpenRecovery: () {},
            onOpenSessions: () {},
          ),
        ),
      );
      await tester.pump();

      final list = find.byKey(const Key('privacy-security-list'));
      final loading = find.byKey(const Key('privacy-security-loading-slot'));
      final alert = find.byKey(const Key('privacy-security-alert-slot'));
      final status = find.byKey(const Key('privacy-security-status-slot'));
      final initialList = _rectOf(tester, list);
      final initialLoading = _rectOf(tester, loading);
      final initialAlert = _rectOf(tester, alert);
      final initialStatus = _rectOf(tester, status);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, loading), initialLoading);
        expect(_rectOf(tester, alert), initialAlert);
        expect(_rectOf(tester, status), initialStatus);
        expect(tester.takeException(), isNull);
      }

      verificationGateway.trust.complete(CrossSigningTrustState.unverified);
      recoveryGateway.status.complete(
        const EncryptionRecoveryStatus(
          backupState: EncryptedBackupState.ready,
          historicalRecoveryState: HistoricalRecoveryState.available,
          hasUnverifiedSessions: false,
        ),
      );
      sessionGateway.devices.complete(const <SessionDevice>[]);
      await tester.pump();

      expect(_rectOf(tester, loading), initialLoading);
      expect(_rectOf(tester, alert), initialAlert);
      expect(_rectOf(tester, status), initialStatus);
    },
  );
}
