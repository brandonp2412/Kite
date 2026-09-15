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

  testWidgets('back navigation has zero late Flutter frames', (tester) async {
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

    final profileFinder = find.byKey(const Key('settings-profile'));
    await tester.tap(profileFinder);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Profile content'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(profileFinder);
    await tester.pumpAndSettle();
    final profileBackResult = await measureFrames(
      binding: binding,
      action: () async {
        Navigator.of(tester.element(find.text('Profile content'))).pop();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(profileFinder, findsOneWidget);

    final privacyFinder = find.byKey(const Key('settings-privacy-security'));
    await tester.ensureVisible(privacyFinder);
    await tester.tap(privacyFinder);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Security content'))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(privacyFinder);

    await tester.tap(privacyFinder);
    await tester.pumpAndSettle();
    final privacyBackResult = await measureFrames(
      binding: binding,
      action: () async {
        Navigator.of(tester.element(find.text('Security content'))).pop();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(privacyFinder, findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['back_from_profile'] = <String, dynamic>{
      'journey': 'back_from_profile',
      'fixture': 'deterministic_back_navigation_v1',
      ...profileBackResult,
      'result': 'PASS',
    };
    binding.reportData!['back_from_privacy_security'] = <String, dynamic>{
      'journey': 'back_from_privacy_security',
      'fixture': 'deterministic_back_navigation_v1',
      ...privacyBackResult,
      'result': 'PASS',
    };
  });
}
