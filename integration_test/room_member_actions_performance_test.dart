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

  testWidgets('member moderation actions have zero late Flutter frames', (
    tester,
  ) async {
    const roleMember = RoomMember(
      userId: '@member:example.org',
      displayName: 'Member',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    const kickMember = RoomMember(
      userId: '@kick:example.org',
      displayName: 'Kick target',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    const banMember = RoomMember(
      userId: '@ban:example.org',
      displayName: 'Ban target',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    const bannedMember = RoomMember(
      userId: '@banned:example.org',
      displayName: 'Banned target',
      membership: RoomMembership.banned,
      powerLevel: 0,
    );
    const reportMember = RoomMember(
      userId: '@report:example.org',
      displayName: 'Report target',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final mutations = FakeRoomMemberMutationPort();
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@moderator:example.org',
      directory: FakeRoomMemberDirectoryPort(
        members: const <RoomMember>[
          roleMember,
          kickMember,
          banMember,
          bannedMember,
          reportMember,
        ],
      ),
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

        await tester.tap(find.byKey(const Key('member-@report:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-report')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('room-report-submit')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-@member:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-role-50')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-@kick:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-kick')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('member-moderation-confirm-Remove')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-@ban:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-ban')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('member-moderation-confirm-Ban')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-@banned:example.org')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-unban')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('member-moderation-confirm-Unban')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('room-safety-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Report room'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('room-report-submit')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('room-safety-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave room'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('member-moderation-confirm-Leave')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('room-safety-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove local room data'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('member-moderation-confirm-Remove data')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(mutations.invitations, isEmpty);
    expect(mutations.powerLevelChanges, hasLength(1));
    expect(mutations.kicks, hasLength(1));
    expect(mutations.bans, hasLength(1));
    expect(mutations.unbans, hasLength(1));
    expect(mutations.userReports, hasLength(1));
    expect(mutations.roomReports, hasLength(1));
    expect(mutations.leaves, hasLength(1));
    expect(mutations.forgottenRooms, hasLength(1));
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_moderation_actions'] = <String, dynamic>{
      'journey': 'room_member_role_moderation_report_leave_forget',
      'fixture': 'deterministic_member_actions_v3',
      ...result,
      'result': 'PASS',
    };
  });
}
