import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/settings/settings_screen.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('settings navigation has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => SettingsScreen(
            accountLabel: '@benchmark:example.org',
            onOpenProfile: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Profile content')),
                ),
              );
            },
            onOpenAccounts: () {},
            onOpenGeneral: () {},
            onOpenNotifications: () {},
            onOpenPrivacySecurity: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('Security content')),
                ),
              );
            },
            onOpenSupport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-profile')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Profile content'))).pop();
    await tester.pumpAndSettle();

    final profileResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('settings-profile')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.text('Profile content'), findsOneWidget);

    Navigator.of(tester.element(find.text('Profile content'))).pop();
    await tester.pumpAndSettle();

    final privacyFinder = find.byKey(const Key('settings-privacy-security'));
    await tester.ensureVisible(privacyFinder);
    await tester.tap(privacyFinder);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Security content'))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(privacyFinder);

    final privacyResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(privacyFinder);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.text('Security content'), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['settings_open_profile'] = <String, dynamic>{
      'journey': 'settings_open_profile',
      'fixture': 'deterministic_settings_navigation_v1',
      ...profileResult,
      'result': 'PASS',
    };
    binding.reportData!['settings_open_privacy_security'] = <String, dynamic>{
      'journey': 'settings_open_privacy_security',
      'fixture': 'deterministic_settings_navigation_v1',
      ...privacyResult,
      'result': 'PASS',
    };
  });
}
