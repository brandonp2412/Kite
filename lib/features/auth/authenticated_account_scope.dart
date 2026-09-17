import 'package:flutter/widgets.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/profile/user_profile_controller.dart';

typedef AuthenticatedAccountSignOut = Future<void> Function();

class AuthenticatedAccountScope extends InheritedWidget {
  const AuthenticatedAccountScope({
    required this.session,
    required this.signOut,
    this.profileController,
    this.recoveryController,
    required super.child,
    super.key,
  });

  final AuthenticatedSession session;
  final AuthenticatedAccountSignOut signOut;
  final UserProfileController? profileController;
  final EncryptionRecoveryController? recoveryController;

  static AuthenticatedAccountScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthenticatedAccountScope>();

  @override
  bool updateShouldNotify(AuthenticatedAccountScope oldWidget) =>
      session.userId != oldWidget.session.userId ||
      session.deviceId != oldWidget.session.deviceId ||
      session.homeserver.uri != oldWidget.session.homeserver.uri ||
      !identical(signOut, oldWidget.signOut) ||
      !identical(profileController, oldWidget.profileController) ||
      !identical(recoveryController, oldWidget.recoveryController);
}
