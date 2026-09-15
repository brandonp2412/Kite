import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_theme.dart';
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

  testWidgets('invite card exposes context and accepts through the port', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final port = _ControlledInvitePort();
    final inviteStore = RoomInviteStore(deterministicRoomInvites, port: port);
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

    expect(find.text('Design Lab'), findsOneWidget);
    expect(find.textContaining('Maya invited you'), findsOneWidget);
    expect(find.text('Polish, motion, and visual review'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invite-accept-design-lab-invite')));
    await tester.pump();
    expect(
      find.byKey(const Key('invite-progress-design-lab-invite')),
      findsOneWidget,
    );
    expect(
      inviteStore.stateSignal('design-lab-invite').value,
      RoomInviteActionState.accepting,
    );

    port.acceptCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-invites')), findsNothing);
    expect(inviteStore.visibleInviteIds.value, isEmpty);
  });
}
