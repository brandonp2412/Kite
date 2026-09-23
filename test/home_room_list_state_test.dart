import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/auth/authenticated_account_scope.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/testing/deterministic_adapters.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

final class _HomeRecoveryGateway implements EncryptionRecoveryGateway {
  static const status = EncryptionRecoveryStatus(
    backupState: EncryptedBackupState.ready,
    historicalRecoveryState: HistoricalRecoveryState.available,
    hasUnverifiedSessions: false,
  );

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async => status;

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async => status;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async => status;

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async => status;

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async => status;
}

final class _HomeProfileGateway implements UserProfileGateway {
  Uri? avatarUri;
  int ownProfileLoads = 0;
  MatrixUserProfile ownProfile = const MatrixUserProfile(
    userId: '@me:example.org',
    displayName: 'Me',
  );

  @override
  Future<MatrixUserProfile> loadOwnProfile() async {
    ownProfileLoads += 1;
    return ownProfile;
  }

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async =>
      MatrixUserProfile(userId: userId);

  @override
  Future<String> openDirectMessage(String userId) async => '!dm:example.org';

  @override
  Future<void> updateDisplayName(String displayName) async {}

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {
    this.avatarUri = avatarUri;
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {}

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {}
}

final class _ExistingDirectRoomPort
    implements RoomManagementPort, DirectMessageOpenPort {
  const _ExistingDirectRoomPort(this.roomId);

  final String roomId;

  @override
  Future<KiteRoomCapabilities> capabilities() async => KiteRoomCapabilities(
    canCreatePublicRooms: true,
    supportedJoinRules: const <KiteRoomJoinRule>{
      KiteRoomJoinRule.invite,
      KiteRoomJoinRule.public,
    },
  );

  @override
  Future<KiteCreatedRoom> openDirectMessage(String userId) async =>
      KiteCreatedRoom(roomId: roomId, isDirect: true, displayName: userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('room-list store updates one stable room signal', () {
    final rooms = deterministicRoomListEntries(BenchmarkFixture.rooms);
    final store = RoomListStateStore(rooms);
    final before = store.roomSignal('alice');

    store.update(
      before.value.copyWith(
        unreadCount: 4,
        hasMention: true,
        avatarUrl: 'mxc://example.org/alice-avatar',
      ),
    );

    expect(store.roomSignal('alice'), same(before));
    expect(before.value.unreadCount, 4);
    expect(before.value.hasMention, isTrue);
    expect(before.value.avatarUrl, 'mxc://example.org/alice-avatar');
  });

  test('locally created room remains visible until sync confirms it', () {
    final rooms = deterministicRoomListEntries(BenchmarkFixture.rooms);
    final store = RoomListStateStore(rooms);
    const pending = RoomListEntry(
      id: '!created:example.org',
      name: 'Created room',
      latestEventBody: '',
      isPendingSync: true,
    );

    store.addPendingRoom(pending);
    expect(store.roomIds.first, pending.id);
    expect(store.roomSignal(pending.id).value.isPendingSync, isTrue);

    store.reconcile(rooms);
    expect(store.roomIds.first, pending.id);
    expect(store.roomSignal(pending.id).value.isPendingSync, isTrue);

    final synced = pending.copyWith(
      latestEventBody: 'Synced activity',
      isPendingSync: false,
    );
    store.reconcile(<RoomListEntry>[...rooms, synced]);

    expect(store.roomIds.last, pending.id);
    expect(store.roomSignal(pending.id).value.isPendingSync, isFalse);
    expect(
      store.roomSignal(pending.id).value.latestEventBody,
      'Synced activity',
    );
  });

  test('client-side hidden rooms stay hidden across sync reconciliation', () {
    final rooms = deterministicRoomListEntries(BenchmarkFixture.rooms);
    final store = RoomListStateStore(rooms);

    store.hideRoom('alice');
    expect(store.visibleRoomIds.value, isNot(contains('alice')));

    store.reconcile(
      rooms
          .map(
            (room) => room.id == 'alice'
                ? room.copyWith(latestEventBody: 'New synced activity')
                : room,
          )
          .toList(growable: false),
    );

    expect(store.isRoomHidden('alice'), isTrue);
    expect(store.visibleRoomIds.value, isNot(contains('alice')));

    store.showRoom('alice');
    expect(store.visibleRoomIds.value, contains('alice'));
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

  testWidgets('focusing an unread room marks that room read', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final previousSelectedRoomId = selectedRoomId.value;
    timelineController.reset(fixtureProvider: (_) => const []);
    addTearDown(() {
      timelineController.reset(fixtureProvider: BenchmarkFixture.messagesFor);
      selectedRoomId.value = previousSelectedRoomId;
    });

    const roomId = '!monday-night-12x12:example.org';
    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: roomId,
        name: 'Monday night 12x12',
        latestEventBody: 'Latest message',
        unreadCount: 20,
      ),
    ]);
    final markedRead = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomListStore: store,
          onMarkRoomRead: (roomId) async {
            markedRead.add(roomId);
            store.update(
              store.roomSignal(roomId).value.copyWith(unreadCount: 0),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('room-unread-$roomId')), findsOneWidget);
    await tester.tap(find.byKey(const Key('room-$roomId')));
    await tester.pump();

    expect(selectedRoomId.value, roomId);
    expect(markedRead, <String>[roomId]);
    expect(find.byKey(const Key('room-unread-$roomId')), findsNothing);
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

  testWidgets('room rows stay neutral and render Matrix avatars', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => selectRoom('kite'));

    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: 'alice',
        name: 'Alice',
        latestEventBody: 'Hello',
        avatarUrl: 'mxc://example.org/alice-avatar',
      ),
    ]);
    selectRoom('alice');
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomListStore: store,
          profileAvatarImageProvider: (_, {dimension}) =>
              MemoryImage(DeterministicImageFixtures.transparentPng1x1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.byKey(const Key('room-alice')));
    expect(tile.selected, isFalse);
    final avatarImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('room-alice')),
        matching: find.byType(Image),
      ),
    );
    expect(avatarImage.image, isA<MemoryImage>());
    expect(avatarImage.errorBuilder, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('room-alice')),
        matching: find.byType(ClipOval),
      ),
      findsOneWidget,
    );
  });

  testWidgets('room options hide chats locally and allow undo', (tester) async {
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
    expect(find.text('Move to section'), findsNothing);
    expect(find.text('Add to favourites'), findsOneWidget);
    expect(find.byKey(const Key('room-hide-alice')), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-favourite-toggle-alice')));
    await tester.pumpAndSettle();
    expect(aliceSignal.value.isFavourite, isTrue);
    expect(favouriteWrites, <({String roomId, bool isFavourite})>[
      (roomId: 'alice', isFavourite: true),
    ]);
    expect(find.text('Remove from favourites'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-hide-alice')));
    await tester.pumpAndSettle();

    expect(store.isRoomHidden('alice'), isTrue);
    expect(find.byKey(const Key('room-alice')), findsNothing);
    expect(store.roomSignal('alice'), same(aliceSignal));
    expect(find.text('Chat hidden on this device.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.isRoomHidden('alice'), isFalse);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
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

  testWidgets('failed read-all persistence keeps local unread state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: 'alice',
        name: 'Alice',
        latestEventBody: 'Unread message',
        unreadCount: 3,
        hasMention: true,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomListStore: store,
          onMarkAllRoomsRead: () async {
            throw StateError('deterministic read-all failure');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('room-alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-mark-all-read-alice')));
    await tester.pumpAndSettle();

    expect(store.roomSignal('alice').value.unreadCount, 3);
    expect(store.roomSignal('alice').value.hasMention, isTrue);
    expect(find.text('Could not mark every chat as read.'), findsOneWidget);
    expect(find.byKey(const Key('room-options-sheet-alice')), findsOneWidget);
  });

  testWidgets('cached Matrix avatar paints before profile hydration', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final session = AuthenticatedSession(
      userId: '@me:example.org',
      deviceId: 'KITE',
      homeserver: HomeserverAddress.parse('https://matrix.example.org'),
    );
    final cachedAvatar = Uri.parse('mxc://example.org/cached-me-avatar');
    var imageProviderCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: AuthenticatedAccountScope(
          session: session,
          signOut: () async {},
          child: HomeScreen(
            profileAvatarFallbackUri: cachedAvatar,
            profileAvatarImageProvider: (avatarUri, {dimension}) {
              imageProviderCalls += 1;
              expect(avatarUri, cachedAvatar);
              return MemoryImage(DeterministicImageFixtures.transparentPng1x1);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(imageProviderCalls, greaterThan(0));
    final accountButton = find.byKey(const Key('home-account-menu'));
    expect(
      find.descendant(of: accountButton, matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('own Matrix avatar loads into the home account button', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final profileGateway = _HomeProfileGateway()
      ..ownProfile = MatrixUserProfile(
        userId: '@me:example.org',
        displayName: 'Me',
        avatarUri: Uri.parse('mxc://example.org/me-avatar'),
      );
    final profile = UserProfileController(profileGateway);
    addTearDown(profile.dispose);
    final session = AuthenticatedSession(
      userId: '@me:example.org',
      deviceId: 'KITE',
      homeserver: HomeserverAddress.parse('https://matrix.example.org'),
    );
    var imageProviderCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: AuthenticatedAccountScope(
          session: session,
          signOut: () async {},
          profileController: profile,
          child: HomeScreen(
            profileAvatarImageProvider: (avatarUri, {dimension}) {
              imageProviderCalls += 1;
              expect(avatarUri, Uri.parse('mxc://example.org/me-avatar'));
              return MemoryImage(DeterministicImageFixtures.transparentPng1x1);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profileGateway.ownProfileLoads, 1);
    expect(imageProviderCalls, greaterThan(0));
    final accountButton = find.byKey(const Key('home-account-menu'));
    expect(accountButton, findsOneWidget);
    expect(
      find.descendant(of: accountButton, matching: find.byType(Image)),
      findsOneWidget,
    );
    final accountImage = tester.widget<Image>(
      find.descendant(of: accountButton, matching: find.byType(Image)),
    );
    expect(accountImage.image, isA<MemoryImage>());
  });

  testWidgets('own profile stays contextual and opens from the account sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final profileGateway = _HomeProfileGateway();
    final profile = UserProfileController(profileGateway);
    addTearDown(profile.dispose);
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
          profileController: profile,
          child: HomeScreen(
            profileAvatarPicker: () async =>
                Uri.parse('mxc://example.org/profile-avatar'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your profile'), findsNothing);
    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-account-profile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-account-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.byKey(const Key('profile-display-name')), findsOneWidget);
    expect(find.text('Me'), findsWidgets);
    expect(find.byKey(const Key('change-profile-avatar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('change-profile-avatar')));
    await tester.pumpAndSettle();
    expect(
      profileGateway.avatarUri,
      Uri.parse('mxc://example.org/profile-avatar'),
    );
  });

  testWidgets(
    'encryption recovery stays contextual and opens from the account sheet',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final recovery = EncryptionRecoveryController(_HomeRecoveryGateway());
      addTearDown(recovery.dispose);
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
            recoveryController: recovery,
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Encryption recovery'), findsNothing);
      await tester.tap(find.byKey(const Key('home-account-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('home-account-encryption-recovery')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('home-account-encryption-recovery')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('encryption-recovery-list')), findsOneWidget);
    },
  );

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
    expect(find.byKey(const Key('home-account-filter-chats')), findsNothing);
    expect(find.byKey(const Key('room-filter-sheet')), findsNothing);
    expect(store.selectedFilter.value, RoomListFilter.all);
  });

  testWidgets(
    'existing direct conversation focuses without replacing the synced room',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const roomId = '!alice:example.org';
      const existing = RoomListEntry(
        id: roomId,
        name: 'Alice',
        latestEventBody: 'Existing message',
        unreadCount: 3,
        isDirect: true,
      );
      final store = RoomListStateStore(const <RoomListEntry>[existing]);
      final coordinator = RoomManagementCoordinator(
        rooms: const _ExistingDirectRoomPort(roomId),
        directMetadata: DeterministicDirectRoomMetadataPort(),
      );
      final previousSelectedRoomId = selectedRoomId.value;
      timelineController.reset(fixtureProvider: (_) => const []);
      addTearDown(() {
        timelineController.reset(fixtureProvider: BenchmarkFixture.messagesFor);
        selectedRoomId.value = previousSelectedRoomId;
      });
      selectedRoomId.value = roomId;

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: HomeScreen(
            roomListStore: store,
            roomCreation: coordinator,
            recentPeople: const <KiteUserSearchResult>[
              KiteUserSearchResult(
                userId: '@alice:example.org',
                displayName: 'Alice',
                avatarUrl: null,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('home-search')), 'Alice');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('create-room-search-result')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('start-direct-message-search-result')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-create-user-result-0')));
      await tester.pumpAndSettle();

      expect(selectedRoomId.value, roomId);
      expect(store.roomIds, const <String>[roomId]);
      expect(store.roomSignal(roomId).value.isPendingSync, isFalse);
      expect(
        store.roomSignal(roomId).value.latestEventBody,
        'Existing message',
      );
      expect(store.roomSignal(roomId).value.unreadCount, 3);
      expect(find.byKey(const Key('room-creation-screen')), findsNothing);
    },
  );

  testWidgets('new room appears immediately while server sync catches up', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final rooms = deterministicRoomListEntries(BenchmarkFixture.rooms);
    final store = RoomListStateStore(rooms);
    final coordinator = RoomManagementCoordinator(
      rooms: DeterministicRoomManagementPort(),
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    final previousSelectedRoomId = selectedRoomId.value;
    timelineController.reset(fixtureProvider: (_) => const []);
    addTearDown(() {
      timelineController.reset(fixtureProvider: BenchmarkFixture.messagesFor);
      selectedRoomId.value = previousSelectedRoomId;
    });
    selectedRoomId.value = rooms.first.id;

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(roomListStore: store, roomCreation: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('home-search')),
      'Created immediately',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-room-search-result')));
    await tester.pumpAndSettle();
    expect(find.text('Create private room'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('room-create-name')),
      'Created immediately',
    );
    await tester.tap(find.byKey(const Key('room-create-submit')));
    await tester.pumpAndSettle();

    const roomId = '!room1:example.org';
    expect(store.roomIds.first, roomId);
    expect(store.roomSignal(roomId).value.name, 'Created immediately');
    expect(store.roomSignal(roomId).value.isPendingSync, isTrue);
    expect(selectedRoomId.value, roomId);
    expect(find.byKey(const Key('room-$roomId')), findsOneWidget);
  });

  testWidgets('search stays pinned at the bottom and offers room creation', (
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
    final rooms = List<RoomListEntry>.generate(
      30,
      (index) => RoomListEntry(
        id: '!room-$index:example.org',
        name: 'Room $index',
        latestEventBody: 'Message $index',
      ),
    );
    final store = RoomListStateStore(rooms);

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(roomListStore: store, roomCreation: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('home-search'));
    final roomList = find.byKey(const Key('room-list'));
    final searchRect = tester.getRect(search);
    expect(
      searchRect.top,
      greaterThanOrEqualTo(tester.getRect(roomList).bottom),
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.fling(roomList, const Offset(0, -700), 2400);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(tester.getRect(search), searchRect);

    await tester.enterText(search, 'Room');
    await tester.pumpAndSettle();

    final createRoom = find.byKey(const Key('create-room-search-result'));
    expect(createRoom, findsOneWidget);
    expect(
      tester.getRect(createRoom).top,
      lessThan(
        tester.getRect(find.byKey(const Key('!room-0:example.org'))).top,
      ),
    );

    await tester.tap(createRoom);
    await tester.pumpAndSettle();
    expect(find.text('Create private room'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
  });

  testWidgets('desktop right-click exposes read-all without home chrome', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const roomId = '!unread:example.org';
    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: roomId,
        name: 'Unread room',
        latestEventBody: 'Latest message',
        unreadCount: 4,
        hasMention: true,
      ),
    ]);
    var persistCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light.copyWith(platform: TargetPlatform.linux),
        home: HomeScreen(
          roomListStore: store,
          onMarkAllRoomsRead: () async {
            persistCalls += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mark all chats as read'), findsNothing);
    final room = find.byKey(const Key('room-$roomId'));
    final detector = tester
        .widgetList<GestureDetector>(
          find.ancestor(of: room, matching: find.byType(GestureDetector)),
        )
        .firstWhere((widget) => widget.onSecondaryTapDown != null);
    detector.onSecondaryTapDown!(
      TapDownDetails(globalPosition: tester.getCenter(room)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mark all chats as read'), findsOneWidget);
    expect(find.byKey(const Key('room-options-sheet-$roomId')), findsNothing);

    await tester.tap(find.byKey(const Key('room-mark-all-read-$roomId')));
    await tester.pumpAndSettle();

    expect(persistCalls, 1);
    expect(store.roomSignal(roomId).value.unreadCount, 0);
    expect(store.roomSignal(roomId).value.hasMention, isFalse);
  });

  testWidgets('desktop right-click can leave a room', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final rooms = DeterministicRoomManagementPort();
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    const roomId = '!kite:example.org';
    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: roomId,
        name: 'Kite',
        latestEventBody: 'Performance test room',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light.copyWith(platform: TargetPlatform.linux),
        home: HomeScreen(roomListStore: store, roomManagement: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    final room = find.byKey(const Key('room-$roomId'));
    final detector = tester
        .widgetList<GestureDetector>(
          find.ancestor(of: room, matching: find.byType(GestureDetector)),
        )
        .firstWhere((widget) => widget.onSecondaryTapDown != null);
    detector.onSecondaryTapDown!(
      TapDownDetails(globalPosition: tester.getCenter(room)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to favourites'), findsOneWidget);
    expect(find.text('Hide chat on this device'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);
    expect(find.byKey(const Key('room-options-sheet-$roomId')), findsNothing);

    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave room?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-remove-confirm')));
    await tester.pumpAndSettle();

    expect(
      rooms.invocations
          .where(
            (entry) => entry.type == RoomManagementInvocationType.leaveRoom,
          )
          .map((entry) => entry.roomId),
      <String>[roomId],
    );
    expect(store.isRoomHidden(roomId), isTrue);
    expect(find.text('Left room.'), findsOneWidget);
  });

  testWidgets('desktop right-click deletes a direct chat', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const directRoomId = '!alice:example.org';
    final previousSelectedRoomId = selectedRoomId.value;
    timelineController.reset(fixtureProvider: (_) => const []);
    addTearDown(() {
      timelineController.reset(fixtureProvider: BenchmarkFixture.messagesFor);
      selectedRoomId.value = previousSelectedRoomId;
    });
    selectedRoomId.value = directRoomId;

    final rooms = DeterministicRoomManagementPort();
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: directRoomId,
        name: 'Alice',
        latestEventBody: 'Hello',
        isDirect: true,
      ),
      RoomListEntry(
        id: '!team:example.org',
        name: 'Team',
        latestEventBody: 'Standup',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light.copyWith(platform: TargetPlatform.linux),
        home: HomeScreen(roomListStore: store, roomManagement: coordinator),
      ),
    );
    await tester.pumpAndSettle();

    final room = find.byKey(const Key('room-$directRoomId'));
    final detector = tester
        .widgetList<GestureDetector>(
          find.ancestor(of: room, matching: find.byType(GestureDetector)),
        )
        .firstWhere((widget) => widget.onSecondaryTapDown != null);
    detector.onSecondaryTapDown!(
      TapDownDetails(globalPosition: tester.getCenter(room)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete chat'), findsOneWidget);
    expect(find.text('Leave room'), findsNothing);

    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();

    expect(find.text('Delete chat?'), findsOneWidget);
    expect(
      find.textContaining('Messages are not deleted for the other person.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('room-remove-confirm')));
    await tester.pumpAndSettle();

    expect(
      rooms.invocations
          .where(
            (entry) =>
                entry.type == RoomManagementInvocationType.leaveRoom ||
                entry.type == RoomManagementInvocationType.forgetRoom,
          )
          .map((entry) => (entry.type, entry.roomId)),
      <(RoomManagementInvocationType, String?)>[
        (RoomManagementInvocationType.leaveRoom, directRoomId),
        (RoomManagementInvocationType.forgetRoom, directRoomId),
      ],
    );
    expect(store.isRoomHidden(directRoomId), isTrue);
    expect(selectedRoomId.value, '!team:example.org');
    expect(find.text('Chat deleted.'), findsOneWidget);
  });

  testWidgets('Ctrl+K jumps to a chat on desktop', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => selectRoom('kite'));

    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light.copyWith(platform: TargetPlatform.linux),
        home: HomeScreen(roomListStore: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-jump-dialog')), findsOneWidget);
    final search = find.byKey(const Key('chat-jump-search'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: search, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(search, 'Alice');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(selectedRoomId.value, 'alice');
    expect(find.byKey(const Key('chat-jump-dialog')), findsNothing);
  });

  testWidgets('account menu omits room creation', (tester) async {
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

    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-account-new-conversation')),
      findsNothing,
    );
    expect(find.text('New conversation'), findsNothing);
  });

  testWidgets('phone chat dismisses with a left-edge swipe', (tester) async {
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

    final roomId = store.roomIds.first;
    await tester.tap(find.byKey(Key('room-$roomId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-chat-screen')), findsOneWidget);
    expect(find.byKey(const Key('compact-chat-edge-swipe')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('compact-chat-edge-swipe')),
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-chat-screen')), findsNothing);
    expect(find.byKey(Key('room-$roomId')), findsOneWidget);
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
