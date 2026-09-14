import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('member invite and role actions have zero late Flutter frames', (
    tester,
  ) async {
    const member = RoomMember(
      userId: '@member:example.org',
      displayName: 'Member',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final mutations = FakeRoomMemberMutationPort();
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@moderator:example.org',
      directory: FakeRoomMemberDirectoryPort(members: <RoomMember>[member]),
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: mutations,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomMembersScreen(
          roomId: '!benchmark:example.org',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('member-invite-action')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-@member:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-role-50')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(mutations.invitations, isEmpty);
    expect(mutations.powerLevelChanges, hasLength(1));
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_invite_role_actions'] = <String, dynamic>{
      'journey': 'room_member_invite_sheet_and_role_change',
      'fixture': 'deterministic_member_actions_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
