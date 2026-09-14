import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';

void main() {
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
