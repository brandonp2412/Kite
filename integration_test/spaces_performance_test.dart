import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/spaces_controller.dart';

import 'performance_benchmark_harness.dart';

Finder _spaceSelector(String spaceId) {
  final chip = find.byKey(Key('spaces-chip-$spaceId'));
  if (chip.evaluate().isNotEmpty) return chip;
  return find.byKey(Key('spaces-rail-$spaceId'));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  tearDown(() => spacesController.reset());

  testWidgets('opening dedicated Spaces stays within the frame contract', (
    tester,
  ) async {
    spacesController.reset();
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('home-spaces')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('spaces-screen')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['spaces_open'] = <String, dynamic>{
      'journey': 'open_spaces',
      'fixture': 'deterministic_spaces_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('Space switch and room join stay within the frame contract', (
    tester,
  ) async {
    spacesController.reset();
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-spaces')));
    await tester.pumpAndSettle();

    final switchResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(_spaceSelector('people-space'));
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(spacesController.selectedSpaceId.value, 'people-space');

    final joinResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('space-room-join-coffee-club')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(
      spacesController.joinStateFor('coffee-club').value,
      SpaceRoomJoinState.joined,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['spaces_switch'] = <String, dynamic>{
      'journey': 'switch_space',
      'fixture': 'deterministic_spaces_v1',
      ...switchResult,
      'result': 'PASS',
    };
    binding.reportData!['spaces_join_room'] = <String, dynamic>{
      'journey': 'join_space_room',
      'fixture': 'deterministic_spaces_v1',
      ...joinResult,
      'result': 'PASS',
    };
  });
}
