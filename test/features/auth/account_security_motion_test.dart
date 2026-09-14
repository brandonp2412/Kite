import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';

final class _DeferredAccountGateway implements AccountManagementGateway {
  final activation = Completer<void>();

  @override
  Future<void> activateAccount(String accountId) => activation.future;

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async {
    return <ManagedMatrixAccount>[
      ManagedMatrixAccount(
        accountId: 'work',
        displayName: 'Work',
        isActive: true,
        session: AuthenticatedSession(
          userId: '@brandon:work.example.org',
          deviceId: 'WORK_DEVICE',
          homeserver: HomeserverAddress.parse('work.example.org'),
        ),
      ),
      ManagedMatrixAccount(
        accountId: 'personal',
        displayName: 'Personal',
        isActive: false,
        session: AuthenticatedSession(
          userId: '@brandon:example.org',
          deviceId: 'PERSONAL_DEVICE',
          homeserver: HomeserverAddress.parse('example.org'),
        ),
      ),
    ];
  }

  @override
  Future<void> signOutAccount(String accountId) async {}
}

final class _StableSessionGateway implements SessionDeviceGateway {
  @override
  Future<List<SessionDevice>> loadDevices() async {
    return const <SessionDevice>[
      SessionDevice(
        deviceId: 'CURRENT',
        displayName: 'Nox',
        isCurrent: true,
        verification: SessionDeviceVerification.verified,
      ),
      SessionDevice(
        deviceId: 'PHONE',
        displayName: 'Phone',
        isCurrent: false,
        verification: SessionDeviceVerification.unverified,
      ),
    ];
  }

  @override
  Future<void> signOutDevice(String deviceId) async {}
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('account switching keeps session geometry stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final accountGateway = _DeferredAccountGateway();
    final accounts = AccountManagementController(accountGateway);
    final devices = SessionDeviceController(_StableSessionGateway());
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSecurityScreen(
          accountController: accounts,
          sessionDeviceController: devices,
          loadOnInit: false,
        ),
      ),
    );

    final list = find.byKey(const Key('account-security-list'));
    final currentDevice = find.byKey(const Key('device-CURRENT'));
    final status = find.byKey(const Key('account-security-status'));
    final initialList = _rectOf(tester, list);
    final initialDevice = _rectOf(tester, currentDevice);
    final initialStatus = _rectOf(tester, status);

    await tester.tap(find.byKey(const Key('activate-account-personal')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, currentDevice), initialDevice);
      expect(_rectOf(tester, status), initialStatus);
      expect(tester.takeException(), isNull);
    }

    accountGateway.activation.complete();
    await tester.pump();
    expect(_rectOf(tester, currentDevice), initialDevice);
    expect(_rectOf(tester, status), initialStatus);
    expect(accounts.activeAccount?.accountId, 'personal');
  });
}
