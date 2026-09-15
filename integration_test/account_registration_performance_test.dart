import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/account_registration_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkRegistrationGateway
    implements AccountRegistrationGateway {
  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) async =>
      const RegistrationCredentialsStep();

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async => const RegistrationInteractiveStep(
    publicInstructions: 'Complete the homeserver challenge.',
  );

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) async => RegistrationCompleteStep(
    AuthenticatedSession(
      userId: '@benchmark:${homeserver.uri.host}',
      deviceId: 'BENCHMARK_DEVICE',
      homeserver: homeserver,
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('account registration has zero late Flutter frames', (
    tester,
  ) async {
    final homeserver = HomeserverAddress.parse('matrix.example.org');
    final gateway = _BenchmarkRegistrationGateway();
    final controller = AccountRegistrationController(
      homeserver: homeserver,
      gateway: gateway,
    );
    addTearDown(controller.dispose);
    await controller.begin();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountRegistrationScreen(
          homeserver: homeserver,
          gateway: gateway,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('registration-username')),
      'benchmark',
    );
    await tester.enterText(
      find.byKey(const Key('registration-password')),
      'benchmark-password',
    );

    final credentialsResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('registration-submit-credentials')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(
      find.byKey(const Key('registration-continue-interactive')),
      findsOneWidget,
    );

    final interactiveResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('registration-continue-interactive')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('registration-complete')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['account_registration_credentials'] = <String, dynamic>{
      'journey': 'account_registration_credentials',
      'fixture': 'deterministic_registration_v1',
      ...credentialsResult,
      'result': 'PASS',
    };
    binding.reportData!['account_registration_interactive'] = <String, dynamic>{
      'journey': 'account_registration_interactive',
      'fixture': 'deterministic_registration_v1',
      ...interactiveResult,
      'result': 'PASS',
    };
  });
}
