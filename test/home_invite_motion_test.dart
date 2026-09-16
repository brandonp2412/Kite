import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';

class _PendingInvitePort implements RoomInvitePort {
  final Completer<void> acceptCompleter = Completer<void>();

  @override
  Future<void> accept(String inviteId) => acceptCompleter.future;

  @override
  Future<void> decline(String inviteId) => Future<void>.value();
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('background invite state does not move simplified home chrome', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final port = _PendingInvitePort();
    final inviteStore = RoomInviteStore(deterministicRoomInvites, port: port);
    final roomStore = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: HomeScreen(roomListStore: roomStore, inviteStore: inviteStore),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('home-search'));
    final roomList = find.byKey(const Key('room-list'));
    final searchRect = _rectOf(tester, search);
    final listRect = _rectOf(tester, roomList);

    final acceptance = inviteStore.accept('design-lab-invite');
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, search), searchRect);
      expect(_rectOf(tester, roomList), listRect);
      expect(find.byKey(const Key('room-invites')), findsNothing);
      expect(tester.takeException(), isNull);
    }

    expect(
      inviteStore.stateSignal('design-lab-invite').value,
      RoomInviteActionState.accepting,
    );
    port.acceptCompleter.complete();
    await acceptance;
    await tester.pumpAndSettle();
  });
}
