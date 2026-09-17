import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';

final class _FakeAccountGateway implements AccountManagementGateway {
  List<ManagedMatrixAccount> loaded = const <ManagedMatrixAccount>[];
  Completer<List<ManagedMatrixAccount>>? deferredLoad;
  final activated = <String>[];
  final signedOut = <String>[];

  @override
  Future<void> activateAccount(String accountId) async {
    activated.add(accountId);
  }

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async {
    final deferred = deferredLoad;
    if (deferred != null) return deferred.future;
    return loaded;
  }

  @override
  Future<void> signOutAccount(String accountId) async {
    signedOut.add(accountId);
  }
}

final class _FakeSessionGateway implements SessionDeviceGateway {
  List<SessionDevice> loaded = const <SessionDevice>[];
  Completer<List<SessionDevice>>? deferredLoad;
  final signedOut = <String>[];
  final signedOutPasswords = <String>[];
  int loadCalls = 0;

  @override
  Future<List<SessionDevice>> loadDevices() async {
    loadCalls += 1;
    final deferred = deferredLoad;
    if (deferred != null) return deferred.future;
    return loaded;
  }

  @override
  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {
    signedOut.add(deviceId);
    signedOutPasswords.add(password);
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

const _personalCurrentDevice = SessionDevice(
  deviceId: 'PERSONAL_DEVICE',
  displayName: 'Personal phone',
  isCurrent: true,
  verification: SessionDeviceVerification.verified,
);

Widget _app({
  required AccountManagementController accounts,
  required SessionDeviceController devices,
  VoidCallback? onAddAccount,
  ValueChanged<ManagedMatrixAccount>? onActiveAccountChanged,
  VoidCallback? onActiveAccountSignedOut,
  bool loadOnInit = false,
}) {
  return MaterialApp(
    home: AccountSecurityScreen(
      accountController: accounts,
      sessionDeviceController: devices,
      onAddAccount: onAddAccount,
      onActiveAccountChanged: onActiveAccountChanged,
      onActiveAccountSignedOut: onActiveAccountSignedOut,
      loadOnInit: loadOnInit,
    ),
  );
}

void main() {
  testWidgets('initial load confirms devices belong to the active session', (
    tester,
  ) async {
    final accountGateway = _FakeAccountGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(id: 'work', userId: '@brandon:work.example.org', active: true),
      ];
    final sessionGateway = _FakeSessionGateway()
      ..loaded = const <SessionDevice>[
        SessionDevice(
          deviceId: 'WORK_DEVICE',
          displayName: 'Work phone',
          isCurrent: true,
          verification: SessionDeviceVerification.verified,
        ),
      ];
    final accounts = AccountManagementController(accountGateway);
    final devices = SessionDeviceController(sessionGateway);
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);

    await tester.pumpWidget(
      _app(accounts: accounts, devices: devices, loadOnInit: true),
    );
    await tester.pumpAndSettle();

    expect(accounts.activeAccount?.session.deviceId, 'WORK_DEVICE');
    expect(devices.currentDevice?.deviceId, 'WORK_DEVICE');
    expect(devices.errorMessage.value, isNull);
  });

  testWidgets('hides remote sign-out until Matrix UIA is available', (
    tester,
  ) async {
    final accounts = AccountManagementController(_FakeAccountGateway());
    final sessionGateway = _FakeSessionGateway()
      ..loaded = const <SessionDevice>[_currentDevice, _remoteDevice];
    final devices = SessionDeviceController(
      sessionGateway,
      remoteSignOutSupported: false,
    );
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();

    await tester.pumpWidget(_app(accounts: accounts, devices: devices));

    expect(find.byKey(const Key('device-CURRENT')), findsOneWidget);
    expect(find.byKey(const Key('device-PHONE')), findsOneWidget);
    expect(find.byKey(const Key('current-device-badge')), findsOneWidget);
    expect(find.byKey(const Key('sign-out-device-PHONE')), findsNothing);
  });

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

      sessionGateway.loaded = const <SessionDevice>[_personalCurrentDevice];
      await tester.tap(find.byKey(const Key('activate-account-personal')));
      await tester.pumpAndSettle();

      expect(accountGateway.activated, <String>['personal']);
      expect(accounts.activeAccount?.accountId, 'personal');
      expect(activatedAccount?.accountId, 'personal');
      expect(sessionGateway.loadCalls, 2);
      expect(find.byKey(const Key('device-CURRENT')), findsNothing);
      expect(find.byKey(const Key('device-PHONE')), findsNothing);
      expect(find.byKey(const Key('device-PERSONAL_DEVICE')), findsOneWidget);
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
    expect(devices.devices.value, isEmpty);
  });

  testWidgets('refresh disables stale account and device mutations', (
    tester,
  ) async {
    final accountGateway = _FakeAccountGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(id: 'work', userId: '@brandon:work.example.org', active: true),
        _account(id: 'personal', userId: '@brandon:example.org', active: false),
      ];
    final sessionGateway = _FakeSessionGateway()
      ..loaded = const <SessionDevice>[_currentDevice, _remoteDevice];
    final accounts = AccountManagementController(accountGateway);
    final devices = SessionDeviceController(sessionGateway);
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();

    accountGateway.deferredLoad = Completer<List<ManagedMatrixAccount>>();
    sessionGateway.deferredLoad = Completer<List<SessionDevice>>();
    final accountRefresh = accounts.load();
    final deviceRefresh = devices.load();
    await tester.pumpWidget(
      _app(accounts: accounts, devices: devices, onAddAccount: () {}),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('activate-account-personal')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('sign-out-account-work')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('sign-out-device-PHONE')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(const Key('add-account'))).onPressed,
      isNull,
    );

    accountGateway.deferredLoad!.complete(accountGateway.loaded);
    sessionGateway.deferredLoad!.complete(sessionGateway.loaded);
    await accountRefresh;
    await deviceRefresh;
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('activate-account-personal')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('sign-out-device-PHONE')))
          .onPressed,
      isNotNull,
    );
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
      find.text('Enter your account password to sign out this session.'),
      findsOneWidget,
    );
    expect(sessionGateway.signedOut, isEmpty);

    await tester.enterText(
      find.byKey(const Key('remote-device-password')),
      'correct horse battery staple',
    );
    await tester.tap(
      find.byKey(const Key('account-security-confirm-Sign out device')),
    );
    await tester.pumpAndSettle();
    expect(sessionGateway.signedOut, <String>['PHONE']);
    expect(sessionGateway.signedOutPasswords, <String>[
      'correct horse battery staple',
    ]);
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
    expect(devices.devices.value, isEmpty);
    expect(find.byKey(const Key('device-CURRENT')), findsNothing);
  });
}
