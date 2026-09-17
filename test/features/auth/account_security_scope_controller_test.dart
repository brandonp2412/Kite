import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_security_scope_controller.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/profile/user_profile_controller.dart';

final class _DeviceGateway implements SessionDeviceGateway {
  int loadCalls = 0;

  @override
  Future<List<SessionDevice>> loadDevices() async {
    loadCalls += 1;
    return const <SessionDevice>[
      SessionDevice(
        deviceId: 'DEVICE',
        isCurrent: true,
        verification: SessionDeviceVerification.verified,
      ),
    ];
  }

  @override
  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {}
}

final class _VerificationGateway implements DeviceVerificationGateway {
  int loadCalls = 0;

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() async {
    loadCalls += 1;
    return CrossSigningTrustState.verified;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecoveryGateway implements EncryptionRecoveryGateway {
  int loadCalls = 0;

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async {
    loadCalls += 1;
    return const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.complete,
      hasUnverifiedSessions: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TrustGateway implements EncryptionTrustGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ProfileGateway implements UserProfileGateway {
  int loadCalls = 0;

  @override
  Future<MatrixUserProfile> loadOwnProfile() async {
    loadCalls += 1;
    return const MatrixUserProfile(userId: '@kite:example.org');
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('account change clears all account-scoped security state', () async {
    final devices = SessionDeviceController(_DeviceGateway());
    final verification = DeviceVerificationController(_VerificationGateway());
    final recovery = EncryptionRecoveryController(_RecoveryGateway());
    final encryptionTrust = EncryptionTrustController(_TrustGateway());
    final profile = UserProfileController(_ProfileGateway());
    addTearDown(devices.dispose);
    addTearDown(verification.dispose);
    addTearDown(recovery.dispose);
    addTearDown(encryptionTrust.dispose);
    addTearDown(profile.dispose);
    final scope = AccountSecurityScopeController(
      sessionDevices: devices,
      verification: verification,
      recovery: recovery,
      encryptionTrust: encryptionTrust,
      profile: profile,
    );

    await devices.load();
    await verification.loadTrust();
    await recovery.refresh();
    await profile.loadOwnProfile();
    expect(devices.devices.value, isNotEmpty);
    expect(verification.trustState.value, CrossSigningTrustState.verified);
    expect(recovery.status.value, isNotNull);
    expect(profile.ownProfile.value, isNotNull);

    scope.resetForAccountChange();

    expect(devices.devices.value, isEmpty);
    expect(verification.trustState.value, CrossSigningTrustState.unknown);
    expect(recovery.status.value, isNull);
    expect(encryptionTrust.state.value, isNull);
    expect(profile.ownProfile.value, isNull);
    expect(profile.ignoredUserIds.value, isEmpty);
    expect(profile.blockedUserIds.value, isEmpty);
  });

  test(
    'account activation refreshes only the new account security state',
    () async {
      final deviceGateway = _DeviceGateway();
      final verificationGateway = _VerificationGateway();
      final recoveryGateway = _RecoveryGateway();
      final profileGateway = _ProfileGateway();
      final devices = SessionDeviceController(deviceGateway);
      final verification = DeviceVerificationController(verificationGateway);
      final recovery = EncryptionRecoveryController(recoveryGateway);
      final encryptionTrust = EncryptionTrustController(_TrustGateway());
      final profile = UserProfileController(profileGateway);
      addTearDown(devices.dispose);
      addTearDown(verification.dispose);
      addTearDown(recovery.dispose);
      addTearDown(encryptionTrust.dispose);
      addTearDown(profile.dispose);
      final scope = AccountSecurityScopeController(
        sessionDevices: devices,
        verification: verification,
        recovery: recovery,
        encryptionTrust: encryptionTrust,
        profile: profile,
      );

      await scope.resetAndRefreshActiveAccount(currentDeviceId: 'DEVICE');

      expect(deviceGateway.loadCalls, 1);
      expect(verificationGateway.loadCalls, 1);
      expect(recoveryGateway.loadCalls, 1);
      expect(profileGateway.loadCalls, 1);
      expect(devices.currentDevice?.deviceId, 'DEVICE');
      expect(verification.trustState.value, CrossSigningTrustState.verified);
      expect(recovery.status.value?.backupState, EncryptedBackupState.ready);
      expect(profile.ownProfile.value?.userId, '@kite:example.org');
      expect(encryptionTrust.state.value, isNull);
    },
  );
}
