import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/auth/authenticated_account_scope.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

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

    final bob = store.roomSignal('bob').value;
    store.update(bob.copyWith(unreadThreadCount: 2));
    store.selectFilter(RoomListFilter.unreads);
    expect(store.visibleRoomIds.value, <String>[
      'kite',
      'alice',
      'bob',
      'room-3',
    ]);

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

  test(
    'sections expose stable grouping, unread state, collapse and room moves',
    () {
      final store = RoomListStateStore(
        deterministicRoomListEntries(BenchmarkFixture.rooms),
      );

      expect(store.sectionIdFor('room-3'), 'favourites');
      expect(store.sectionIdFor('alice'), 'people');
      expect(store.sectionIdFor('kite'), 'rooms');
      expect(store.sectionUnreadCount('favourites'), 1);
      expect(store.sectionUnreadCount('people'), 1);
      expect(store.sectionUnreadCount('rooms'), 1);

      store.toggleSectionCollapsed('people');
      expect(store.collapsedSectionIds.value, contains('people'));
      store.toggleSectionCollapsed('people');
      expect(store.collapsedSectionIds.value, isNot(contains('people')));

      final revision = store.sectionLayoutRevision.value;
      store.moveRoomToSection('alice', 'favourites');
      expect(store.sectionIdFor('alice'), 'favourites');
      expect(store.sectionLayoutRevision.value, revision + 1);
      expect(
        store.visibleRoomIdsForSection('favourites'),
        containsAllInOrder(<String>['alice', 'room-3']),
      );
    },
  );

  test('favourite state stays leaf-level and preserves section identity', () {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final aliceSignal = store.roomSignal('alice');

    store.toggleFavourite('alice');
    expect(store.roomSignal('alice'), same(aliceSignal));
    expect(aliceSignal.value.isFavourite, isTrue);
    expect(store.sectionIdFor('alice'), 'people');

    store.toggleFavourite('alice');
    expect(aliceSignal.value.isFavourite, isFalse);
    expect(store.sectionIdFor('alice'), 'people');
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

  testWidgets(
    'muted rooms use a quiet activity marker instead of unread chrome',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final store = RoomListStateStore(const <RoomListEntry>[
        RoomListEntry(
          id: '!muted:example.org',
          name: 'Muted room',
          latestEventBody: 'New activity',
          unreadCount: 5,
          hasMutedActivity: true,
          isMuted: true,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: HomeScreen(roomListStore: store),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('room-muted-activity-!muted:example.org')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('room-unread-!muted:example.org')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('room-muted-!muted:example.org')),
        findsOneWidget,
      );
    },
  );

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

  testWidgets('room options move chats without replacing room state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final aliceSignal = store.roomSignal('alice');
    final favouriteWrites = <({String roomId, bool isFavourite})>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomListStore: store,
          onRoomFavouriteChanged: (roomId, isFavourite) async {
            favouriteWrites.add((roomId: roomId, isFavourite: isFavourite));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-section-people')), findsNothing);

    await tester.longPress(find.byKey(const Key('room-alice')));
    await tester.pumpAndSettle();
    expect(find.text('Room options'), findsOneWidget);
    expect(find.text('Move to section'), findsOneWidget);
    expect(find.text('Add to favourites'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-favourite-toggle-alice')));
    await tester.pumpAndSettle();
    expect(aliceSignal.value.isFavourite, isTrue);
    expect(favouriteWrites, <({String roomId, bool isFavourite})>[
      (roomId: 'alice', isFavourite: true),
    ]);
    expect(store.sectionIdFor('alice'), 'people');
    expect(find.text('Remove from favourites'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-section-move-alice-rooms')));
    await tester.pumpAndSettle();

    expect(store.sectionIdFor('alice'), 'rooms');
    expect(store.roomSignal('alice'), same(aliceSignal));
  });

  testWidgets('failed favourite persistence rolls optimistic state back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final aliceSignal = store.roomSignal('alice');
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomListStore: store,
          onRoomFavouriteChanged: (_, _) async {
            throw StateError('deterministic favourite failure');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('room-alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-favourite-toggle-alice')));
    await tester.pumpAndSettle();

    expect(aliceSignal.value.isFavourite, isFalse);
    expect(find.text('Add to favourites'), findsOneWidget);
    expect(find.text('Could not update favourite.'), findsOneWidget);
  });

  testWidgets('contextual room filters stay off the home surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final session = AuthenticatedSession(
      userId: '@me:example.org',
      deviceId: 'KITE',
      homeserver: HomeserverAddress.parse('https://matrix.example.org'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: AuthenticatedAccountScope(
          session: session,
          signOut: () async {},
          child: HomeScreen(roomListStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-filter-row')), findsNothing);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-kite')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-account-filter-chats')), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-account-filter-chats')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-filter-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('room-filter-option-people')));
    await tester.pumpAndSettle();

    expect(store.selectedFilter.value, RoomListFilter.people);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsOneWidget);
    expect(find.byKey(const Key('room-kite')), findsNothing);
    expect(find.byKey(const Key('room-room-3')), findsNothing);

    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();
    expect(find.text('People'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-account-filter-chats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-filter-option-favourites')));
    await tester.pumpAndSettle();

    expect(store.selectedFilter.value, RoomListFilter.favourites);
    expect(find.byKey(const Key('room-room-3')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsNothing);
    expect(find.byKey(const Key('room-filter-row')), findsNothing);
  });

  testWidgets('room creation stays in the contextual account menu', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final coordinator = RoomManagementCoordinator(
      rooms: DeterministicRoomManagementPort(),
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    final session = AuthenticatedSession(
      userId: '@me:example.org',
      deviceId: 'KITE',
      homeserver: HomeserverAddress.parse('https://matrix.example.org'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: AuthenticatedAccountScope(
          session: session,
          signOut: () async {},
          child: HomeScreen(roomCreation: coordinator),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New conversation'), findsNothing);
    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('home-account-new-conversation')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('home-account-new-conversation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-creation-screen')), findsOneWidget);
  });

  testWidgets('search is the only persistent homepage chat filter', (
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

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.byKey(const Key('space-filter-row')), findsNothing);
    expect(find.byKey(const Key('room-filter-row')), findsNothing);

    await tester.enterText(find.byKey(const Key('home-search')), 'Alice');
    await tester.pump();
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsNothing);
    expect(find.byKey(const Key('room-kite')), findsNothing);

    await tester.tap(find.byKey(const Key('home-search-clear')));
    await tester.pump();
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-bob')), findsOneWidget);
    expect(find.byKey(const Key('room-kite')), findsOneWidget);
  });
}
