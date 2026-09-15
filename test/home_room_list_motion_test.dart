import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';

void main() {
  testWidgets('filter transition preserves header and filter-row geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(roomListStore: store),
      ),
    );
    await tester.pumpAndSettle();

    final profile = find.byKey(const Key('home-profile'));
    final filterRow = find.byKey(const Key('room-filter-row'));
    final list = find.byKey(const Key('room-list'));
    final profileRect = tester.getRect(profile);
    final filterRect = tester.getRect(filterRow);
    final listRect = tester.getRect(list);

    await tester.tap(find.byKey(const Key('room-filter-people')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(tester.getRect(profile), profileRect);
    expect(tester.getRect(filterRow), filterRect);
    expect(tester.getRect(list).top, listRect.top);
    expect(store.selectedFilter.value, RoomListFilter.people);
  });

  testWidgets('space transition keeps sidebar geometry fixed at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(roomListStore: store),
      ),
    );
    await tester.pumpAndSettle();

    final profile = find.byKey(const Key('home-profile'));
    final spaceRow = find.byKey(const Key('space-filter-row'));
    final filterRow = find.byKey(const Key('room-filter-row'));
    final list = find.byKey(const Key('room-list'));
    final profileRect = tester.getRect(profile);
    final spaceRect = tester.getRect(spaceRow);
    final filterRect = tester.getRect(filterRow);
    final listRect = tester.getRect(list);

    await tester.tap(find.byKey(const Key('space-filter-kite-space')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(profile), profileRect);
      expect(tester.getRect(spaceRow), spaceRect);
      expect(tester.getRect(filterRow), filterRect);
      expect(tester.getRect(list), listRect);
      expect(tester.takeException(), isNull);
    }

    expect(store.selectedSpaceId.value, 'kite-space');
    expect(find.byKey(const Key('room-kite')), findsOneWidget);
    expect(find.byKey(const Key('room-room-3')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsNothing);
  });

  testWidgets(
    'leaf room-state update preserves list geometry and scroll anchor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final store = RoomListStateStore(
        deterministicRoomListEntries(BenchmarkFixture.rooms),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: HomeScreen(roomListStore: store),
        ),
      );
      await tester.pump();

      final list = find.byKey(const Key('room-list'));
      await tester.drag(list, const Offset(0, -360));
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      final roomFinder = find.byKey(const Key('room-room-5'));
      expect(roomFinder, findsOne);
      final beforeRect = tester.getRect(roomFinder);
      final beforePixels = scrollable.position.pixels;

      final room = store.roomSignal('room-5').value;
      store.update(
        room.copyWith(
          latestSender: 'Dana',
          latestEventBody: 'A new mention without geometry movement',
          unreadCount: 7,
          hasMention: true,
          isMuted: true,
          isFavourite: true,
        ),
      );
      await tester.pump();

      expect(tester.getRect(roomFinder), beforeRect);
      expect(scrollable.position.pixels, beforePixels);
      expect(find.byKey(const Key('room-mention-room-5')), findsOne);
      expect(find.byKey(const Key('room-muted-room-5')), findsOne);
      expect(find.byKey(const Key('room-favourite-room-5')), findsOne);
      expect(find.text('@7'), findsOne);
    },
  );
}
