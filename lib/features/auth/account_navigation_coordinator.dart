import 'package:flutter/material.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_scope_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';

final class AccountNavigationCoordinator {
  const AccountNavigationCoordinator({
    required this.profileController,
    required this.accountController,
    required this.sessionDeviceController,
    required this.onOpenRoom,
    this.securityScopeController,
    this.pickAvatar,
    this.avatarImageProvider,
    this.onAddAccount,
    this.onActiveAccountChanged,
    this.onActiveAccountSignedOut,
  });

  final UserProfileController profileController;
  final AccountManagementController accountController;
  final SessionDeviceController sessionDeviceController;
  final AccountSecurityScopeController? securityScopeController;
  final ValueChanged<String> onOpenRoom;
  final AvatarPicker? pickAvatar;
  final AvatarImageProvider? avatarImageProvider;
  final VoidCallback? onAddAccount;
  final ValueChanged<ManagedMatrixAccount>? onActiveAccountChanged;
  final VoidCallback? onActiveAccountSignedOut;

  Future<void> openOwnProfile(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen.own(
          controller: profileController,
          pickAvatar: pickAvatar,
          avatarImageProvider: avatarImageProvider,
        ),
      ),
    );
  }

  Future<void> openUserProfile(BuildContext context, String userId) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen.user(
          controller: profileController,
          userId: userId,
          onOpenRoom: onOpenRoom,
          avatarImageProvider: avatarImageProvider,
        ),
      ),
    );
  }

  Future<void> openAccountsAndSessions(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccountSecurityScreen(
          accountController: accountController,
          sessionDeviceController: sessionDeviceController,
          securityScopeController: securityScopeController,
          onAddAccount: onAddAccount,
          onActiveAccountChanged: onActiveAccountChanged,
          onActiveAccountSignedOut: onActiveAccountSignedOut,
        ),
      ),
    );
  }
}
