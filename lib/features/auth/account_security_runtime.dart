import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/account_security_scope_controller.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/matrix_account_sdk_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/auth/session_lifecycle.dart';
import 'package:kite/features/notifications/push_registration.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';

final class AccountSecurityRuntime {
  factory AccountSecurityRuntime(MatrixAccountSdkBoundary boundary) {
    final gateway = MatrixAccountSdkGateway(boundary);
    final sessionDevices = SessionDeviceController(gateway);
    final verification = DeviceVerificationController(gateway);
    final recovery = EncryptionRecoveryController(gateway);
    final encryptionTrust = EncryptionTrustController(gateway);
    final profile = UserProfileController(gateway);
    return AccountSecurityRuntime._(
      gateway: gateway,
      authentication: AuthenticationController(gateway),
      lifecycle: SessionLifecycleController(gateway),
      verification: verification,
      recovery: recovery,
      encryptionTrust: encryptionTrust,
      sessionDevices: sessionDevices,
      accounts: AccountManagementController(gateway),
      profile: profile,
      pushRegistration: PushRegistrationController(gateway),
      scope: AccountSecurityScopeController(
        sessionDevices: sessionDevices,
        verification: verification,
        recovery: recovery,
        encryptionTrust: encryptionTrust,
        profile: profile,
      ),
    );
  }

  const AccountSecurityRuntime._({
    required this.gateway,
    required this.authentication,
    required this.lifecycle,
    required this.verification,
    required this.recovery,
    required this.encryptionTrust,
    required this.sessionDevices,
    required this.accounts,
    required this.profile,
    required this.pushRegistration,
    required this.scope,
  });

  final MatrixAccountSdkGateway gateway;
  final AuthenticationController authentication;
  final SessionLifecycleController lifecycle;
  final DeviceVerificationController verification;
  final EncryptionRecoveryController recovery;
  final EncryptionTrustController encryptionTrust;
  final SessionDeviceController sessionDevices;
  final AccountManagementController accounts;
  final UserProfileController profile;
  final PushRegistrationController pushRegistration;
  final AccountSecurityScopeController scope;

  AccountRegistrationController registrationFor(HomeserverAddress homeserver) {
    return AccountRegistrationController(
      homeserver: homeserver,
      gateway: gateway,
    );
  }

  void dispose() {
    authentication.dispose();
    lifecycle.dispose();
    verification.dispose();
    recovery.dispose();
    encryptionTrust.dispose();
    sessionDevices.dispose();
    accounts.dispose();
    profile.dispose();
    pushRegistration.dispose();
  }
}
