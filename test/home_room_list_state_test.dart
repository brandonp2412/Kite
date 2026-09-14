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
    expect(find.byKey(const Key('room-active-call-bob')), findsOne);
    expect(find.byKey(const Key('room-unread-room-3')), findsOne);
    expect(find.text('4'), findsOne);
  });
}
