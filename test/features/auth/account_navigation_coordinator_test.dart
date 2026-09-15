import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_navigation_coordinator.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/profile/user_profile_controller.dart';

final class _ProfileGateway implements UserProfileGateway {
  String? openedUserId;

  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => const <String>{};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async => const MatrixUserProfile(
    userId: '@brandon:example.org',
    displayName: 'Brandon',
  );

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async =>
      MatrixUserProfile(
        userId: userId,
        displayName: userId == '@alice:example.org' ? 'Alice' : null,
      );

  @override
  Future<String> openDirectMessage(String userId) async {
    openedUserId = userId;
    return '!dm:example.org';
  }

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {}

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {}

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}
}

final class _AccountGateway implements AccountManagementGateway {
  @override
  Future<void> activateAccount(String accountId) async {}

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async =>
      <ManagedMatrixAccount>[
        ManagedMatrixAccount(
          accountId: 'personal',
          displayName: 'Personal',
          isActive: true,
          session: AuthenticatedSession(
            userId: '@brandon:example.org',
            deviceId: 'CURRENT',
            homeserver: HomeserverAddress.parse('matrix.example.org'),
          ),
        ),
      ];

  @override
  Future<void> signOutAccount(String accountId) async {}
}

final class _SessionGateway implements SessionDeviceGateway {
  @override
  Future<List<SessionDevice>> loadDevices() async => const <SessionDevice>[
    SessionDevice(
      deviceId: 'CURRENT',
      displayName: 'Nox',
      isCurrent: true,
      verification: SessionDeviceVerification.verified,
    ),
  ];

  @override
  Future<void> signOutDevice(String deviceId) async {}
}

void main() {
  testWidgets(
    'routes account profile and session flows through shared controllers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final profileGateway = _ProfileGateway();
      final profileController = UserProfileController(profileGateway);
      final accountController = AccountManagementController(_AccountGateway());
      final sessionController = SessionDeviceController(_SessionGateway());
      addTearDown(profileController.dispose);
      addTearDown(accountController.dispose);
      addTearDown(sessionController.dispose);

      String? openedRoomId;
      late AccountNavigationCoordinator coordinator;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              coordinator = AccountNavigationCoordinator(
                profileController: profileController,
                accountController: accountController,
                sessionDeviceController: sessionController,
                onOpenRoom: (roomId) => openedRoomId = roomId,
              );
              return Scaffold(
                body: Column(
                  children: <Widget>[
                    FilledButton(
                      key: const Key('open-own-profile'),
                      onPressed: () => coordinator.openOwnProfile(context),
                      child: const Text('Own profile'),
                    ),
                    FilledButton(
                      key: const Key('open-user-profile'),
                      onPressed: () => coordinator.openUserProfile(
                        context,
                        '@alice:example.org',
                      ),
                      child: const Text('User profile'),
                    ),
                    FilledButton(
                      key: const Key('open-accounts'),
                      onPressed: () =>
                          coordinator.openAccountsAndSessions(context),
                      child: const Text('Accounts'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-own-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Your profile'), findsOneWidget);
      expect(find.text('Brandon'), findsWidgets);
      Navigator.of(tester.element(find.text('Your profile'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-user-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-message')));
      await tester.pump();
      expect(profileGateway.openedUserId, '@alice:example.org');
      expect(openedRoomId, '!dm:example.org');
      Navigator.of(tester.element(find.text('Alice'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-accounts')));
      await tester.pumpAndSettle();
      expect(find.text('Accounts & sessions'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Nox'), findsOneWidget);
    },
  );
}
