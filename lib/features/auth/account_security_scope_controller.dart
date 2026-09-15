import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/profile/user_profile_controller.dart';

final class AccountSecurityScopeController {
  const AccountSecurityScopeController({
    required this.sessionDevices,
    required this.verification,
    required this.recovery,
    required this.encryptionTrust,
    required this.profile,
  });

  final SessionDeviceController sessionDevices;
  final DeviceVerificationController verification;
  final EncryptionRecoveryController recovery;
  final EncryptionTrustController encryptionTrust;
  final UserProfileController profile;

  void resetForAccountChange() {
    sessionDevices.resetForAccountChange();
    verification.resetForAccountChange();
    recovery.resetForAccountChange();
    encryptionTrust.resetForAccountChange();
    profile.resetForAccountChange();
  }

  Future<void> resetAndRefreshActiveAccount() async {
    resetForAccountChange();
    await Future.wait<void>(<Future<void>>[
      sessionDevices.load(),
      verification.loadTrust(),
      recovery.refresh().then<void>((_) {}),
      profile.loadOwnProfile(),
    ]);
  }
}
