import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

final class _DeferredMemberDirectory implements RoomMemberDirectoryPort {
  _DeferredMemberDirectory(this.initialMembers);

  final List<RoomMember> initialMembers;
  Completer<List<RoomMember>>? pendingSearch;

  @override
  Future<RoomPowerLevelSummary> powerLevels(String roomId) async {
    return RoomPowerLevelSummary(
      members: const <String, int>{},
      defaultUserPowerLevel: 0,
    );
  }

  @override
  Future<List<RoomMember>> searchMembers({
    required String roomId,
    required String query,
  }) {
    if (query.isEmpty) return Future<List<RoomMember>>.value(initialMembers);
    pendingSearch = Completer<List<RoomMember>>();
    return pendingSearch!.future;
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('member search preserves heading and field geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final directory = _DeferredMemberDirectory(const <RoomMember>[
      RoomMember(
        userId: '@alice:example.org',
        displayName: 'Alice',
        membership: RoomMembership.joined,
        powerLevel: 0,
      ),
    ]);
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@moderator:example.org',
      directory: directory,
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomMembersScreen(
          roomId: '!team:example.org',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heading = find.text('Members');
    final search = find.byKey(const Key('member-search'));
    final initialHeading = _rectOf(tester, heading);
    final initialSearch = _rectOf(tester, search);

    await tester.enterText(search, 'ali');
    expect(directory.pendingSearch, isNotNull);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, heading), initialHeading);
      expect(_rectOf(tester, search), initialSearch);
      expect(tester.takeException(), isNull);
    }

    directory.pendingSearch!.complete(const <RoomMember>[
      RoomMember(
        userId: '@alice:example.org',
        displayName: 'Alice',
        membership: RoomMembership.joined,
        powerLevel: 0,
      ),
    ]);
    await tester.pump();

    expect(_rectOf(tester, heading), initialHeading);
    expect(_rectOf(tester, search), initialSearch);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets(
    'member overlays keep the underlying room geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final member = const RoomMember(
        userId: '@alice:example.org',
        displayName: 'Alice',
        membership: RoomMembership.joined,
        powerLevel: 0,
      );
      final coordinator = RoomMemberManagementCoordinator(
        actorUserId: '@moderator:example.org',
        directory: FakeRoomMemberDirectoryPort(members: <RoomMember>[member]),
        authorization: FakeRoomMemberAuthorizationPort(),
        mutations: FakeRoomMemberMutationPort(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: RoomMembersScreen(
            roomId: '!team:example.org',
            coordinator: coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final heading = find.text('Members');
      final search = find.byKey(const Key('member-search'));
      final initialHeading = _rectOf(tester, heading);
      final initialSearch = _rectOf(tester, search);

      await tester.tap(find.byKey(const Key('member-invite-action')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, heading), initialHeading);
        expect(_rectOf(tester, search), initialSearch);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('member-invite-user-id')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-@alice:example.org')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, heading), initialHeading);
        expect(_rectOf(tester, search), initialSearch);
        expect(tester.takeException(), isNull);
      }

      expect(find.byKey(const Key('member-details-name')), findsOneWidget);
      expect(find.byKey(const Key('member-role-50')), findsOneWidget);
      expect(find.byKey(const Key('member-role-100')), findsOneWidget);
    },
  );
}
