import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/benchmark/room_list_benchmark_surface.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('room search and filters have zero late Flutter frames', (
    tester,
  ) async {
    final controller = RoomListBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RoomListBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      controller.visibleRooms.value,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.search('Benchmark room 2999');
        await tester.pump();
        controller.search('');
        controller.selectFilter(BenchmarkRoomFilter.unread);
        await tester.pump();
        controller.selectFilter(BenchmarkRoomFilter.people);
        await tester.pump();
        controller.selectFilter(BenchmarkRoomFilter.favourites);
        await tester.pump();
        controller.selectFilter(BenchmarkRoomFilter.all);
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(
      controller.visibleRooms.value,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_search_filter'] = <String, dynamic>{
      'journey': 'room_search_filter',
      'fixture': 'deterministic_3000_rooms_v2',
      'roomCount': BenchmarkFixture.largeRoomListRooms.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('Spaces and Sections switching has zero late Flutter frames', (
    tester,
  ) async {
    final controller = RoomListBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RoomListBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.selectSpace('space-3');
        await tester.pump();
        controller.selectFilter(BenchmarkRoomFilter.people);
        await tester.pump();
        controller.selectFilter(BenchmarkRoomFilter.unread);
        await tester.pump();
        controller.selectSpace('space-1');
        controller.selectFilter(BenchmarkRoomFilter.all);
        await tester.pump();
        controller.selectSpace(null);
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.spaceId, isNull);
    expect(controller.filter, BenchmarkRoomFilter.all);
    expect(
      controller.visibleRooms.value,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['spaces_sections_switch'] = <String, dynamic>{
      'journey': 'spaces_sections_switch',
      'fixture': 'deterministic_5_spaces_3000_rooms_v1',
      'roomCount': BenchmarkFixture.largeRoomListRooms.length,
      ...result,
      'result': 'PASS',
    };
  });
}
