import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/home_screen.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('3,000-room list scroll has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(benchmarkRooms: BenchmarkFixture.largeRoomListRooms),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      BenchmarkFixture.largeRoomListRooms,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final list = find.byKey(const Key('room-list'));
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1200), 5000);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_scroll_3000'] = <String, dynamic>{
      'journey': 'room_list_scroll',
      'fixture': 'deterministic_3000_rooms_v1',
      'roomCount': BenchmarkFixture.largeRoomListRooms.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('composer keyboard appearance has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final composer = find.descendant(
      of: find.byKey(const Key('composer')),
      matching: find.byType(TextField),
    );
    expect(composer, findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(composer);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_keyboard'] = <String, dynamic>{
      'journey': 'composer_keyboard',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
