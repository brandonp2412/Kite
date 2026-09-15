import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/room_list_filter.dart';

void main() {
  testWidgets('room filters expose deterministic Element X-style categories', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    selectRoom('kite');
    selectRoomListFilter(RoomListFilter.all);
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-filter-bar')), findsOneWidget);
    expect(find.byKey(const Key('room-kite')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-unreads')));
    await tester.pump();
    expect(activeRoomListFilter.value, RoomListFilter.unreads);
    expect(find.byKey(const Key('room-kite')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-people')));
    await tester.pump();
    expect(activeRoomListFilter.value, RoomListFilter.people);
    expect(find.byKey(const Key('room-kite')), findsNothing);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsOneWidget);

    selectRoomListFilter(RoomListFilter.favourites);
    await tester.pump();
    expect(find.byKey(const Key('room-kite')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsNothing);
  });
}
