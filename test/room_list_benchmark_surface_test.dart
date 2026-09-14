import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/benchmark/room_list_benchmark_surface.dart';

void main() {
  testWidgets('room-list benchmark filtering is deterministic', (tester) async {
    final controller = RoomListBenchmarkController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RoomListBenchmarkSurface(controller: controller)),
    );

    expect(
      controller.visibleRooms.value,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );

    controller.search('Benchmark room 2999');
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(1));

    controller.search('');
    controller.selectFilter(BenchmarkRoomFilter.unread);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(750));

    controller.selectFilter(BenchmarkRoomFilter.people);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(1000));

    controller.selectFilter(BenchmarkRoomFilter.favourites);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(300));
  });

  testWidgets('space and section switching compose deterministically', (
    tester,
  ) async {
    final controller = RoomListBenchmarkController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RoomListBenchmarkSurface(controller: controller)),
    );

    controller.selectSpace('space-3');
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(600));

    controller.selectFilter(BenchmarkRoomFilter.people);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(200));

    controller.selectFilter(BenchmarkRoomFilter.unread);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(150));

    controller.selectSpace('space-1');
    controller.selectFilter(BenchmarkRoomFilter.all);
    await tester.pump();
    expect(controller.visibleRooms.value, hasLength(600));
    expect(find.byKey(const Key('benchmark-room-list')), findsOneWidget);
    expect(find.text('600 rooms'), findsOneWidget);
  });
}
