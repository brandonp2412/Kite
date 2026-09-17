import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_device_controller.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkAccountGateway implements AccountManagementGateway {
  @override
  Future<void> activateAccount(String accountId) async {}

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async {
    return <ManagedMatrixAccount>[
      ManagedMatrixAccount(
        accountId: 'work',
        displayName: 'Work',
        isActive: true,
        session: AuthenticatedSession(
          userId: '@benchmark:work.example.org',
          deviceId: 'WORK_DEVICE',
          homeserver: HomeserverAddress.parse('work.example.org'),
        ),
      ),
      ManagedMatrixAccount(
        accountId: 'personal',
        displayName: 'Personal',
        isActive: false,
        session: AuthenticatedSession(
          userId: '@benchmark:example.org',
          deviceId: 'PERSONAL_DEVICE',
          homeserver: HomeserverAddress.parse('example.org'),
        ),
      ),
    ];
  }

  @override
  Future<void> signOutAccount(String accountId) async {}
}

final class _BenchmarkSessionDeviceGateway implements SessionDeviceGateway {
  @override
  Future<List<SessionDevice>> loadDevices() async {
    return const <SessionDevice>[
      SessionDevice(
        deviceId: 'CURRENT',
        displayName: 'Benchmark device',
        isCurrent: true,
        verification: SessionDeviceVerification.verified,
      ),
      SessionDevice(
        deviceId: 'REMOTE',
        displayName: 'Remote device',
        isCurrent: false,
        verification: SessionDeviceVerification.unverified,
      ),
    ];
  }

  @override
  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('account and session management have zero late Flutter frames', (
    tester,
  ) async {
    final accounts = AccountManagementController(_BenchmarkAccountGateway());
    final devices = SessionDeviceController(_BenchmarkSessionDeviceGateway());
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
    await tester.pumpAndSettle();

    final switchResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('activate-account-personal')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(accounts.activeAccount?.accountId, 'personal');

    final remoteSignOutResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('sign-out-device-REMOTE')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('account-security-confirm-Sign out device')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('device-REMOTE')), findsNothing);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['account_switch'] = <String, dynamic>{
      'journey': 'account_switch',
      'fixture': 'deterministic_account_security_v1',
      ...switchResult,
      'result': 'PASS',
    };
    binding.reportData!['remote_session_sign_out'] = <String, dynamic>{
      'journey': 'remote_session_sign_out',
      'fixture': 'deterministic_account_security_v1',
      ...remoteSignOutResult,
      'result': 'PASS',
    };
  });
}
