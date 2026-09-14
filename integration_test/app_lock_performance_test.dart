import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_lock_gate.dart';
import 'package:kite/features/settings/app_lock_settings_screen.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkAppLockCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings(
    enabled: true,
    biometricsEnabled: true,
    hideNotificationContents: true,
  );
  final String pin = '1234';

  @override
  Future<void> disable() async {
    stored = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    stored = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async => stored;

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == this.pin;
}

final class _BenchmarkBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'warm app lock settings mutations have zero late Flutter frames',
    (tester) async {
      final credentials = _BenchmarkAppLockCredentials();
      final controller = AppLockController(credentials, _BenchmarkBiometrics());
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final biometrics = find.byKey(const Key('app-lock-biometrics'));
      final privacy = find.byKey(const Key('app-lock-hide-notifications'));
      await tester.tap(biometrics);
      await tester.pumpAndSettle();
      await tester.tap(biometrics);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(biometrics);
          await tester.pumpAndSettle();
          await tester.tap(privacy);
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(controller.settings.value.biometricsEnabled, isFalse);
      expect(controller.settings.value.hideNotificationContents, isFalse);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['app_lock_settings_mutations'] = <String, dynamic>{
        'journey': 'app_lock_settings_mutations',
        'fixture': 'deterministic_app_lock_v1',
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets('warm app unlock has zero late Flutter frames', (tester) async {
    final credentials = _BenchmarkAppLockCredentials();
    final controller = AppLockController(credentials, _BenchmarkBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          loadOnInit: false,
          child: const SizedBox.expand(key: Key('protected-app-content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await controller.unlockWithPin('1234'), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protected-app-content')), findsOneWidget);

    controller.lock();
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        expect(await controller.unlockWithPin('1234'), isTrue);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.isLocked.value, isFalse);
    expect(find.byKey(const Key('protected-app-content')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['app_unlock'] = <String, dynamic>{
      'journey': 'app_unlock',
      'fixture': 'deterministic_app_lock_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
