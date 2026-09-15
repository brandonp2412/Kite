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

  testWidgets('room member list scroll has zero late Flutter frames', (
    tester,
  ) async {
    final members = List<RoomMember>.generate(
      200,
      (index) => RoomMember(
        userId: '@member$index:example.org',
        displayName: 'Member $index',
        membership: RoomMembership.joined,
        powerLevel: index == 0 ? 100 : (index % 17 == 0 ? 50 : 0),
      ),
      growable: false,
    );
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@member0:example.org',
      directory: FakeRoomMemberDirectoryPort(members: members),
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
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

    final list = find.byKey(const Key('member-list'));
    expect(list, findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1200), 5000);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('member-list')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_list_scroll_200'] = <String, dynamic>{
      'journey': 'room_member_list_scroll',
      'fixture': 'deterministic_200_members_v1',
      'memberCount': members.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('room member search/filter stays within the frame budget', (
    tester,
  ) async {
    final members = List<RoomMember>.generate(
      200,
      (index) => RoomMember(
        userId: '@member$index:example.org',
        displayName: 'Member $index',
        membership: RoomMembership.joined,
        powerLevel: index == 0 ? 100 : 0,
      ),
      growable: false,
    );
    final directory = FakeRoomMemberDirectoryPort(members: members);
    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@member0:example.org',
      directory: directory,
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
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

    final search = find.byKey(const Key('member-search'));
    expect(search, findsOneWidget);

    final textField = tester.widget<TextField>(search);
    final result = await measureFrames(
      binding: binding,
      action: () async {
        textField.controller!.text = 'member 199';
        textField.onChanged!('member 199');
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(directory.queries, contains('member 199'));
    expect(find.text('Member 199'), findsOneWidget);
    expect(find.text('Member 198'), findsNothing);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_member_search_filter_200'] = <String, dynamic>{
      'journey': 'search_filter_room_members',
      'fixture': 'deterministic_200_members_v1',
      'memberCount': members.length,
      'query': 'member 199',
      ...result,
      'result': 'PASS',
    };
  });
}
