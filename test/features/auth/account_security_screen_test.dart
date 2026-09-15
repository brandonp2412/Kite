import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';

final class _FakeAccountGateway implements AccountManagementGateway {
  List<ManagedMatrixAccount> loaded = const <ManagedMatrixAccount>[];
  final activated = <String>[];
  final signedOut = <String>[];

  @override
  Future<void> activateAccount(String accountId) async {
    activated.add(accountId);
  }

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async => loaded;

  @override
  Future<void> signOutAccount(String accountId) async {
    signedOut.add(accountId);
  }
}

final class _FakeSessionGateway implements SessionDeviceGateway {
  List<SessionDevice> loaded = const <SessionDevice>[];
  final signedOut = <String>[];

  @override
  Future<List<SessionDevice>> loadDevices() async => loaded;

  @override
  Future<void> signOutDevice(String deviceId) async {
    signedOut.add(deviceId);
  }
}

ManagedMatrixAccount _account({
  required String id,
  required String userId,
  required bool active,
}) {
  return ManagedMatrixAccount(
    accountId: id,
    displayName: id == 'personal' ? 'Personal' : 'Work',
    isActive: active,
    session: AuthenticatedSession(
      userId: userId,
      deviceId: '${id.toUpperCase()}_DEVICE',
      homeserver: HomeserverAddress.parse('matrix.example.org'),
    ),
  );
}

const _currentDevice = SessionDevice(
  deviceId: 'CURRENT',
  displayName: 'Nox',
  isCurrent: true,
  verification: SessionDeviceVerification.verified,
);

const _remoteDevice = SessionDevice(
  deviceId: 'PHONE',
  displayName: 'Phone',
  isCurrent: false,
  verification: SessionDeviceVerification.unverified,
);

Widget _app({
  required AccountManagementController accounts,
  required SessionDeviceController devices,
  VoidCallback? onAddAccount,
  ValueChanged<ManagedMatrixAccount>? onActiveAccountChanged,
  VoidCallback? onActiveAccountSignedOut,
}) {
  return MaterialApp(
    home: AccountSecurityScreen(
      accountController: accounts,
      sessionDeviceController: devices,
      onAddAccount: onAddAccount,
      onActiveAccountChanged: onActiveAccountChanged,
      onActiveAccountSignedOut: onActiveAccountSignedOut,
      loadOnInit: false,
    ),
  );
}

void main() {
  testWidgets(
    'shows current account, account switching and device verification state',
    (tester) async {
      final accountGateway = _FakeAccountGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            id: 'work',
            userId: '@brandon:work.example.org',
            active: true,
          ),
          _account(
            id: 'personal',
            userId: '@brandon:example.org',
            active: false,
          ),
        ];
      final sessionGateway = _FakeSessionGateway()
        ..loaded = const <SessionDevice>[_currentDevice, _remoteDevice];
      final accounts = AccountManagementController(accountGateway);
      final devices = SessionDeviceController(sessionGateway);
      addTearDown(accounts.dispose);
      addTearDown(devices.dispose);
      await accounts.load();
      await devices.load();

      ManagedMatrixAccount? activatedAccount;
      await tester.pumpWidget(
        _app(
          accounts: accounts,
          devices: devices,
          onActiveAccountChanged: (account) => activatedAccount = account,
        ),
      );

      expect(find.text('Accounts & sessions'), findsOneWidget);
      expect(find.byKey(const Key('active-account-badge')), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(
        find.byKey(const Key('activate-account-personal')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('current-device-badge')), findsOneWidget);
      expect(find.textContaining('CURRENT · Verified'), findsOneWidget);
      expect(find.textContaining('PHONE · Unverified'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activate-account-personal')));
      await tester.pump();

      expect(accountGateway.activated, <String>['personal']);
      expect(accounts.activeAccount?.accountId, 'personal');
      expect(activatedAccount?.accountId, 'personal');
    },
  );

  testWidgets('exposes add-account and active sign-out lifecycle callbacks', (
    tester,
  ) async {
    final accountGateway = _FakeAccountGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(id: 'work', userId: '@brandon:work.example.org', active: true),
      ];
    final accounts = AccountManagementController(accountGateway);
    final devices = SessionDeviceController(_FakeSessionGateway());
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();
    var addAccountCalls = 0;
    var activeSignOutCalls = 0;

    await tester.pumpWidget(
      _app(
        accounts: accounts,
        devices: devices,
        onAddAccount: () => addAccountCalls += 1,
        onActiveAccountSignedOut: () => activeSignOutCalls += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('add-account')));
    expect(addAccountCalls, 1);

    await tester.tap(find.byKey(const Key('sign-out-account-work')));
    await tester.pumpAndSettle();
    expect(activeSignOutCalls, 0);
    await tester.tap(
      find.byKey(const Key('account-security-confirm-Sign out')),
    );
    await tester.pumpAndSettle();

    expect(accountGateway.signedOut, <String>['work']);
    expect(activeSignOutCalls, 1);
  });

  testWidgets('confirms remote session and account sign-out before mutation', (
    tester,
  ) async {
    final accountGateway = _FakeAccountGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(id: 'work', userId: '@brandon:work.example.org', active: true),
      ];
    final sessionGateway = _FakeSessionGateway()
      ..loaded = const <SessionDevice>[_currentDevice, _remoteDevice];
    final accounts = AccountManagementController(accountGateway);
    final devices = SessionDeviceController(sessionGateway);
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();

    await tester.pumpWidget(_app(accounts: accounts, devices: devices));

    await tester.tap(find.byKey(const Key('sign-out-device-PHONE')));
    await tester.pumpAndSettle();
    expect(
      find.text('This Matrix session will be remotely signed out.'),
      findsOneWidget,
    );
    expect(sessionGateway.signedOut, isEmpty);

    await tester.tap(
      find.byKey(const Key('account-security-confirm-Sign out device')),
    );
    await tester.pumpAndSettle();
    expect(sessionGateway.signedOut, <String>['PHONE']);
    expect(find.byKey(const Key('device-PHONE')), findsNothing);

    await tester.tap(find.byKey(const Key('sign-out-account-work')));
    await tester.pumpAndSettle();
    expect(accountGateway.signedOut, isEmpty);

    await tester.tap(
      find.byKey(const Key('account-security-confirm-Sign out')),
    );
    await tester.pumpAndSettle();
    expect(accountGateway.signedOut, <String>['work']);
    expect(find.byKey(const Key('account-work')), findsNothing);
  });
}
