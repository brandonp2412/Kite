import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';

Future<Map<String, dynamic>> _measureFrames({
  required IntegrationTestWidgetsFlutterBinding binding,
  required Future<void> Function() action,
  required bool enforceTotalSpan,
}) async {
  final timings = <FrameTiming>[];
  void callback(List<FrameTiming> values) => timings.addAll(values);

  await Future<void>.delayed(const Duration(seconds: 1));
  binding.addTimingsCallback(callback);
  await action();
  await Future<void>.delayed(const Duration(seconds: 1));
  binding.removeTimingsCallback(callback);

  expect(timings, isNotEmpty);
  final rawRefreshRate =
      binding.platformDispatcher.views.first.display.refreshRate;
  final refreshRate = rawRefreshRate > 0 ? rawRefreshRate : 60.0;
  final budgetUs = (1000000 / refreshRate).floor();
  final buildViolations = timings
      .where((timing) => timing.buildDuration.inMicroseconds > budgetUs)
      .length;
  final rasterViolations = timings
      .where((timing) => timing.rasterDuration.inMicroseconds > budgetUs)
      .length;
  final totalSpanViolations = timings
      .where((timing) => timing.totalSpan.inMicroseconds > budgetUs)
      .length;

  expect(buildViolations, PerformanceContract.maxBuildBudgetViolations);
  expect(rasterViolations, PerformanceContract.maxRasterBudgetViolations);
  if (enforceTotalSpan) {
    expect(
      totalSpanViolations,
      PerformanceContract.maxTotalSpanBudgetViolations,
    );
  }

  return <String, dynamic>{
    'refreshRateHz': refreshRate,
    'frameBudgetUs': budgetUs,
    'frames': timings.length,
    'buildBudgetViolations': buildViolations,
    'rasterBudgetViolations': rasterViolations,
    'totalSpanBudgetViolations': totalSpanViolations,
    'totalSpanGated': enforceTotalSpan,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  testWidgets('opening room details has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final detailsButton = find.byKey(const Key('room-details-button'));
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('room-details-screen'))))
        .pop();
    await tester.pumpAndSettle();

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(detailsButton);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('room-details-screen')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_details_open'] = <String, dynamic>{
      'journey': 'open_room_details',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('warmed member search has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('member-search'));
    await tester.tap(search);
    await tester.enterText(search, 'a');
    await tester.pumpAndSettle();

    final searchResult = await _measureFrames(
      binding: binding,
      action: () async {
        await tester.enterText(search, 'bob');
        await tester.pump();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('member-@bob:example.org')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_search'] = <String, dynamic>{
      'journey': 'filter_member_list_warm_ime',
      'fixture': 'deterministic_v1',
      ...searchResult,
      'result': 'PASS',
    };
  });

  testWidgets('warmed member profile open has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();

    final bob = find.byKey(const Key('member-@bob:example.org'));
    await tester.tap(bob);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('member-profile-sheet'))))
        .pop();
    await tester.pumpAndSettle();

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(bob);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('member-profile-sheet')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_profile'] = <String, dynamic>{
      'journey': 'open_member_profile',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('promoting a room member has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-@bob:example.org')));
    await tester.pumpAndSettle();

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('member-promote')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('Power 50'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_promote'] = <String, dynamic>{
      'journey': 'promote_room_member',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('kicking a room member has zero late Flutter frames', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-@bob:example.org')));
    await tester.pumpAndSettle();

    final result = await _measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('member-kick')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-kick-confirm')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('member-kick-confirm')), findsNothing);
    expect(find.byKey(const Key('member-profile-sheet')), findsNothing);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_kick'] = <String, dynamic>{
      'journey': 'kick_room_member',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
