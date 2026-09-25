import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/auth/authenticated_account_scope.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';

class _ControlledInvitePort implements RoomInvitePort {
  final Completer<void> acceptCompleter = Completer<void>();
  final Completer<void> declineCompleter = Completer<void>();

  @override
  Future<void> accept(String inviteId) => acceptCompleter.future;

  @override
  Future<void> decline(String inviteId) => declineCompleter.future;
}

class _FailingInvitePort implements RoomInvitePort {
  @override
  Future<void> accept(String inviteId) =>
      Future<void>.error(StateError('failed'));

  @override
  Future<void> decline(String inviteId) =>
      Future<void>.error(StateError('failed'));
}

void main() {
  test(
    'invite store exposes deterministic pending, success, and failure states',
    () async {
      final port = _ControlledInvitePort();
      final store = RoomInviteStore(deterministicRoomInvites, port: port);
      const inviteId = 'design-lab-invite';

      final acceptFuture = store.accept(inviteId);
      expect(
        store.stateSignal(inviteId).value,
        RoomInviteActionState.accepting,
      );
      expect(store.visibleInviteIds.value, <String>[inviteId]);

      port.acceptCompleter.complete();
      await acceptFuture;
      expect(store.visibleInviteIds.value, isEmpty);

      final failingStore = RoomInviteStore(
        deterministicRoomInvites,
        port: _FailingInvitePort(),
      );
      await failingStore.decline(inviteId);
      expect(
        failingStore.stateSignal(inviteId).value,
        RoomInviteActionState.failed,
      );
      expect(failingStore.visibleInviteIds.value, <String>[inviteId]);
    },
  );

  testWidgets(
    'account sheet exposes invite cards and actions off the home surface',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final inviteStore = RoomInviteStore(deterministicRoomInvites);
      final roomStore = RoomListStateStore(
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
            child: HomeScreen(
              roomListStore: roomStore,
              inviteStore: inviteStore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Design Lab'), findsNothing);
      await tester.tap(find.byKey(const Key('home-account-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-account-invites')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-account-invites')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-invites-sheet')), findsOneWidget);
      expect(find.text('Design Lab'), findsOneWidget);
      expect(find.textContaining('Invited by Maya'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('invite-accept-design-lab-invite')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No pending invites'), findsOneWidget);
      expect(inviteStore.visibleInviteIds.value, isEmpty);
    },
  );

  testWidgets(
    'Space invite preview shows Space identity visibility and context',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final inviteStore = RoomInviteStore(const <RoomInvite>[
        RoomInvite(
          id: 'community-space',
          roomName: 'Community',
          inviterName: 'Alice',
          memberCount: 42,
          description: 'Community projects and planning',
          isSpace: true,
          isExternal: true,
          visibility: RoomInviteVisibility.public,
        ),
      ]);
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
            child: HomeScreen(inviteStore: inviteStore),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-account-invites')));
      await tester.pumpAndSettle();

      expect(find.text('Community'), findsOneWidget);
      expect(
        find.byKey(const Key('invite-space-kind-community-space')),
        findsOneWidget,
      );
      expect(find.text('External Space'), findsOneWidget);
      expect(find.textContaining('Invited by Alice'), findsOneWidget);
      expect(find.textContaining('42 members'), findsOneWidget);
      expect(find.textContaining('Public access'), findsOneWidget);
      expect(
        find.textContaining('Community projects and planning'),
        findsOneWidget,
      );
    },
  );

  testWidgets('homepage keeps invite cards out of the chat list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inviteStore = RoomInviteStore(deterministicRoomInvites);
    final roomStore = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(roomListStore: roomStore, inviteStore: inviteStore),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.byKey(const Key('room-list')), findsOneWidget);
    expect(find.text('Design Lab'), findsNothing);
    expect(find.byKey(const Key('room-invites')), findsNothing);
    expect(inviteStore.visibleInviteIds, isNotNull);
  });
}
