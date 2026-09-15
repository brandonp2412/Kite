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
  testWidgets('invite pending state preserves surrounding geometry at 120 Hz', (
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

    final inviteCard = find.byKey(
      const ValueKey<String>('invite-design-lab-invite'),
    );
    final roomList = find.byKey(const Key('room-list'));
    final spaceRow = find.byKey(const Key('space-filter-row'));
    final inviteRect = _rectOf(tester, inviteCard);
    final listRect = _rectOf(tester, roomList);
    final spaceRect = _rectOf(tester, spaceRow);

    await tester.tap(find.byKey(const Key('invite-accept-design-lab-invite')));

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, inviteCard), inviteRect);
      expect(_rectOf(tester, roomList), listRect);
      expect(_rectOf(tester, spaceRow), spaceRect);
      expect(tester.takeException(), isNull);
    }

    expect(
      find.byKey(const Key('invite-progress-design-lab-invite')),
      findsOneWidget,
    );
    port.acceptCompleter.complete();
    await tester.pumpAndSettle();
  });
}
