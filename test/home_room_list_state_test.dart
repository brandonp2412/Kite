import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';

void main() {
  test('room-list store updates one stable room signal', () {
    final rooms = deterministicRoomListEntries(BenchmarkFixture.rooms);
    final store = RoomListStateStore(rooms);
    final before = store.roomSignal('alice');

    store.update(before.value.copyWith(unreadCount: 4, hasMention: true));

    expect(store.roomSignal('alice'), same(before));
    expect(before.value.unreadCount, 4);
    expect(before.value.hasMention, isTrue);
  });

  test('room-list filters preserve deterministic ordering and membership', () {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );

    store.selectFilter(RoomListFilter.people);
    expect(store.visibleRoomIds.value, <String>['alice', 'bob']);

    store.selectFilter(RoomListFilter.unreads);
    expect(store.visibleRoomIds.value, <String>['kite', 'alice', 'room-3']);

    store.selectFilter(RoomListFilter.favourites);
    expect(store.visibleRoomIds.value, <String>['room-3']);

    store.selectFilter(RoomListFilter.rooms);
    expect(store.visibleRoomIds.value.first, 'kite');
    expect(store.visibleRoomIds.value, isNot(contains('alice')));
    expect(store.visibleRoomIds.value, isNot(contains('bob')));
  });

  test('space selection composes with room filters without reordering', () {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );

    store.selectSpace('kite-space');
    expect(store.visibleRoomIds.value, <String>['kite', 'room-3']);

    store.selectFilter(RoomListFilter.favourites);
    expect(store.visibleRoomIds.value, <String>['room-3']);

    store.selectSpace('people-space');
    expect(store.visibleRoomIds.value, isEmpty);

    store.selectFilter(RoomListFilter.people);
    expect(store.visibleRoomIds.value, <String>['alice', 'bob']);

    store.selectSpace(null);
    expect(store.visibleRoomIds.value, <String>['alice', 'bob']);
  });

  test(
    'mark all read clears unread membership without touching room identity',
    () {
      final store = RoomListStateStore(
        deterministicRoomListEntries(BenchmarkFixture.rooms),
      );
      final kiteSignal = store.roomSignal('kite');
      final favouriteSignal = store.roomSignal('room-3');

      store.selectFilter(RoomListFilter.unreads);
      store.markAllRead();

      expect(store.visibleRoomIds.value, isEmpty);
      expect(store.roomSignal('kite'), same(kiteSignal));
      expect(store.roomSignal('room-3'), same(favouriteSignal));
      expect(kiteSignal.value.unreadCount, 0);
      expect(kiteSignal.value.hasMention, isFalse);
      expect(store.roomSignal('alice').value.hasMutedActivity, isFalse);
      expect(favouriteSignal.value.isFavourite, isTrue);
    },
  );

  test('room-list store rejects duplicate IDs', () {
    const room = RoomListEntry(
      id: 'duplicate',
      name: 'Duplicate',
      latestEventBody: 'One',
    );
    expect(
      () => RoomListStateStore(const <RoomListEntry>[room, room]),
      throwsArgumentError,
    );
  });

  testWidgets('room rows render sender attribution and status decorations', (
    tester,
  ) async {
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

    expect(find.text('Maya: The room-list motion trace is clean.'), findsOne);
    expect(find.byKey(const Key('room-mention-kite')), findsOne);
    expect(find.text('@12'), findsOne);
    expect(find.byKey(const Key('room-muted-activity-alice')), findsOne);
    expect(find.byKey(const Key('room-muted-alice')), findsOne);
    expect(find.byKey(const Key('room-active-call-bob')), findsOne);
    expect(find.byKey(const Key('room-unread-room-3')), findsOne);
    expect(find.byKey(const Key('room-favourite-room-3')), findsOne);
    expect(find.text('4'), findsOne);
  });

  testWidgets('filter controls and read-all action drive visible room state', (
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

    expect(find.byKey(const Key('space-filter-all')), findsOneWidget);
    expect(find.byKey(const Key('space-filter-kite-space')), findsOneWidget);
    expect(find.byKey(const Key('space-filter-people-space')), findsOneWidget);

    await tester.tap(find.byKey(const Key('space-filter-people-space')));
    await tester.pumpAndSettle();
    expect(store.selectedSpaceId.value, 'people-space');
    expect(find.byKey(const Key('room-alice')), findsOne);
    expect(find.byKey(const Key('room-bob')), findsOne);
    expect(find.byKey(const Key('room-kite')), findsNothing);

    await tester.tap(find.byKey(const Key('space-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-filter-people')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-alice')), findsOne);
    expect(find.byKey(const Key('room-bob')), findsOne);
    expect(find.byKey(const Key('room-kite')), findsNothing);

    await tester.tap(find.byKey(const Key('room-filter-unreads')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-kite')), findsOne);
    expect(find.byKey(const Key('room-room-3')), findsOne);

    await tester.tap(find.byKey(const Key('home-read-all')));
    await tester.pumpAndSettle();
    expect(store.visibleRoomIds.value, isEmpty);
    expect(find.byKey(const Key('room-kite')), findsNothing);
  });
}
