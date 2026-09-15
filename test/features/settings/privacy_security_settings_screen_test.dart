import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/settings/privacy_security_settings_screen.dart';

final class _VerificationGateway implements DeviceVerificationGateway {
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
  Future<CrossSigningTrustState> loadCrossSigningTrust() async =>
      CrossSigningTrustState.unverified;

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

final class _RecoveryGateway implements EncryptionRecoveryGateway {
  static const status = EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.needsRecovery,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: true,
  );

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async => status;

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async => status;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async => status;

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async => status;

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async => status;
}

final class _SessionGateway implements SessionDeviceGateway {
  @override
  Future<List<SessionDevice>> loadDevices() async => const <SessionDevice>[
    SessionDevice(
      deviceId: 'CURRENT',
      isCurrent: true,
      verification: SessionDeviceVerification.verified,
    ),
    SessionDevice(
      deviceId: 'REMOTE',
      isCurrent: false,
      verification: SessionDeviceVerification.unverified,
    ),
  ];

  @override
  Future<void> signOutDevice(String deviceId) async {}
}

void main() {
  testWidgets('unknown security state is never presented as healthy', (
    tester,
  ) async {
    final verification = DeviceVerificationController(_VerificationGateway());
    final recovery = EncryptionRecoveryController(_RecoveryGateway());
    final sessions = SessionDeviceController(_SessionGateway());
    addTearDown(verification.dispose);
    addTearDown(recovery.dispose);
    addTearDown(sessions.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacySecuritySettingsScreen(
          verificationController: verification,
          recoveryController: recovery,
          sessionDeviceController: sessions,
          loadOnInit: false,
          onOpenVerification: () {},
          onOpenRecovery: () {},
          onOpenSessions: () {},
        ),
      ),
    );

    expect(find.text('Security status incomplete'), findsOneWidget);
    expect(
      find.text(
        'Some verification, recovery, or session status is unavailable.',
      ),
      findsOneWidget,
    );
    expect(find.text('Security looks good'), findsNothing);
  });

  testWidgets(
    'unknown device verification never presents security as healthy',
    (tester) async {
      final verification = DeviceVerificationController(_VerificationGateway());
      final recovery = EncryptionRecoveryController(_RecoveryGateway());
      final sessions = SessionDeviceController(_SessionGateway());
      addTearDown(verification.dispose);
      addTearDown(recovery.dispose);
      addTearDown(sessions.dispose);
      verification.trustState.value = CrossSigningTrustState.verified;
      recovery.status.value = const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.ready,
        historicalRecoveryState: HistoricalRecoveryState.complete,
        hasUnverifiedSessions: false,
      );
      sessions.devices.value = const <SessionDevice>[
        SessionDevice(
          deviceId: 'CURRENT',
          isCurrent: true,
          verification: SessionDeviceVerification.verified,
        ),
        SessionDevice(
          deviceId: 'REMOTE',
          isCurrent: false,
          verification: SessionDeviceVerification.unknown,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacySecuritySettingsScreen(
            verificationController: verification,
            recoveryController: recovery,
            sessionDeviceController: sessions,
            loadOnInit: false,
            onOpenVerification: () {},
            onOpenRecovery: () {},
            onOpenSessions: () {},
          ),
        ),
      );

      expect(find.text('Security status incomplete'), findsOneWidget);
      expect(find.text('2 devices · 1 status unknown'), findsOneWidget);
      expect(find.text('Security looks good'), findsNothing);
    },
  );

  testWidgets('summarizes verification, recovery, sessions and app lock', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final verification = DeviceVerificationController(_VerificationGateway());
    final recovery = EncryptionRecoveryController(_RecoveryGateway());
    final sessions = SessionDeviceController(_SessionGateway());
    addTearDown(verification.dispose);
    addTearDown(recovery.dispose);
    addTearDown(sessions.dispose);
    await verification.loadTrust();
    await recovery.refresh();
    await sessions.load();

    var verificationOpens = 0;
    var recoveryOpens = 0;
    var sessionOpens = 0;
    var userControlsOpens = 0;
    var appLockOpens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacySecuritySettingsScreen(
          verificationController: verification,
          recoveryController: recovery,
          sessionDeviceController: sessions,
          loadOnInit: false,
          appLockEnabled: true,
          onOpenVerification: () => verificationOpens += 1,
          onOpenRecovery: () => recoveryOpens += 1,
          onOpenSessions: () => sessionOpens += 1,
          onOpenUserControls: () => userControlsOpens += 1,
          onOpenAppLock: () => appLockOpens += 1,
        ),
      ),
    );

    expect(find.text('Security action recommended'), findsOneWidget);
    expect(
      find.text(
        'Verify untrusted sessions and review encrypted-backup recovery.',
      ),
      findsOneWidget,
    );
    expect(find.text('Verification required'), findsOneWidget);
    expect(find.text('Recovery needs attention'), findsOneWidget);
    expect(find.text('2 devices · 1 unverified'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('security-review-verification')));
    await tester.tap(find.byKey(const Key('security-review-recovery')));
    await tester.tap(find.byKey(const Key('privacy-security-verification')));
    await tester.tap(find.byKey(const Key('privacy-security-recovery')));
    await tester.tap(find.byKey(const Key('privacy-security-sessions')));
    await tester.tap(find.byKey(const Key('privacy-security-user-controls')));
    await tester.tap(find.byKey(const Key('privacy-security-app-lock')));

    expect(verificationOpens, 2);
    expect(recoveryOpens, 2);
    expect(sessionOpens, 1);
    expect(userControlsOpens, 1);
    expect(appLockOpens, 1);
  });
}
