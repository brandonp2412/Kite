import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

void main() {
  const roomId = '!team:example.org';
  const actorUserId = '@moderator:example.org';

  RoomMemberManagementCoordinator coordinator({
    required FakeRoomMemberDirectoryPort directory,
    FakeRoomMemberAuthorizationPort? authorization,
    FakeRoomMemberMutationPort? mutations,
  }) {
    return RoomMemberManagementCoordinator(
      actorUserId: actorUserId,
      directory: directory,
      authorization: authorization ?? FakeRoomMemberAuthorizationPort(),
      mutations: mutations ?? FakeRoomMemberMutationPort(),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required RoomMemberManagementCoordinator coordinator,
    bool safetyActionsEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomMembersScreen(
          roomId: roomId,
          coordinator: coordinator,
          safetyActionsEnabled: safetyActionsEnabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('member list searches live and opens exact member details', (
    tester,
  ) async {
    final directory = FakeRoomMemberDirectoryPort(
      members: const <RoomMember>[
        RoomMember(
          userId: '@alice:example.org',
          displayName: 'Alice',
          membership: RoomMembership.joined,
          powerLevel: 0,
        ),
        RoomMember(
          userId: '@bob:example.org',
          displayName: 'Bob',
          membership: RoomMembership.joined,
          powerLevel: 50,
        ),
      ],
    );
    await pumpScreen(tester, coordinator: coordinator(directory: directory));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('member-search')), 'bob');
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    expect(directory.queries, <String>['', 'bob']);

    await tester.tap(find.byKey(const Key('member-@bob:example.org')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-details-name')), findsOneWidget);
    expect(find.byKey(const Key('member-details-user-id')), findsOneWidget);
    expect(find.text('Moderator'), findsWidgets);
    expect(find.text('Power level 50'), findsOneWidget);
  });

  testWidgets('invite action delegates an exact Matrix user ID', (
    tester,
  ) async {
    final directory = FakeRoomMemberDirectoryPort();
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(directory: directory, mutations: mutations),
    );

    await tester.tap(find.byKey(const Key('member-invite-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('member-invite-user-id')),
      '  @new:example.org  ',
    );
    await tester.tap(find.byKey(const Key('member-invite-submit')));
    await tester.pumpAndSettle();

    expect(mutations.invitations, <({String roomId, String userId})>[
      (roomId: roomId, userId: '@new:example.org'),
    ]);
    expect(find.byKey(const Key('member-error')), findsOneWidget);
    expect(
      find.text('Enter a valid Matrix user ID, such as @name:server.'),
      findsNothing,
    );
  });

  testWidgets(
    'production-style member screen keeps invite while hiding unsupported safety actions',
    (tester) async {
      final member = const RoomMember(
        userId: '@member:example.org',
        displayName: 'Member',
        membership: RoomMembership.joined,
        powerLevel: 0,
      );
      await pumpScreen(
        tester,
        coordinator: coordinator(
          directory: FakeRoomMemberDirectoryPort(members: <RoomMember>[member]),
        ),
        safetyActionsEnabled: false,
      );

      expect(find.byKey(const Key('member-invite-action')), findsOneWidget);
      expect(find.byKey(const Key('room-safety-actions')), findsNothing);

      await tester.tap(find.byKey(const Key('member-@member:example.org')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('member-report')), findsNothing);
    },
  );

  testWidgets('role actions expose only SDK-authorised target power levels', (
    tester,
  ) async {
    final member = const RoomMember(
      userId: '@member:example.org',
      displayName: 'Member',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final directory = FakeRoomMemberDirectoryPort(
      members: <RoomMember>[member],
    );
    final authorization = FakeRoomMemberAuthorizationPort(
      resolver: (request) {
        if (request.action == RoomMemberAction.changePowerLevel &&
            request.requestedPowerLevel == 50) {
          return const RoomMemberActionAuthorization.allowed();
        }
        return const RoomMemberActionAuthorization.denied(
          'Role change not permitted.',
        );
      },
    );
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(
        directory: directory,
        authorization: authorization,
        mutations: mutations,
      ),
    );

    await tester.tap(find.byKey(const Key('member-@member:example.org')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-role-50')), findsOneWidget);
    expect(find.byKey(const Key('member-role-100')), findsNothing);
    expect(find.byKey(const Key('member-role-0')), findsNothing);

    await tester.tap(find.byKey(const Key('member-role-50')));
    await tester.pumpAndSettle();

    expect(
      mutations.powerLevelChanges,
      <({String roomId, String userId, int powerLevel})>[
        (roomId: roomId, userId: member.userId, powerLevel: 50),
      ],
    );
  });

  testWidgets('kick is permission gated and requires confirmation', (
    tester,
  ) async {
    const member = RoomMember(
      userId: '@member:example.org',
      displayName: 'Member',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final directory = FakeRoomMemberDirectoryPort(
      members: const <RoomMember>[member],
    );
    final authorization = FakeRoomMemberAuthorizationPort(
      resolver: (request) {
        if (request.action == RoomMemberAction.kick) {
          return const RoomMemberActionAuthorization.allowed();
        }
        return const RoomMemberActionAuthorization.denied('Not permitted.');
      },
    );
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(
        directory: directory,
        authorization: authorization,
        mutations: mutations,
      ),
    );

    await tester.tap(find.byKey(const Key('member-@member:example.org')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-kick')), findsOneWidget);
    expect(find.byKey(const Key('member-ban')), findsNothing);
    await tester.tap(find.byKey(const Key('member-kick')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Member?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(mutations.kicks, isEmpty);

    await tester.tap(find.byKey(const Key('member-kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-moderation-confirm-Remove')));
    await tester.pumpAndSettle();

    expect(mutations.kicks, <({String roomId, String userId})>[
      (roomId: roomId, userId: member.userId),
    ]);
  });

  testWidgets('ban transitions to authorised unban semantics', (tester) async {
    const member = RoomMember(
      userId: '@member:example.org',
      displayName: 'Member',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final directory = FakeRoomMemberDirectoryPort(
      members: const <RoomMember>[member],
    );
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(directory: directory, mutations: mutations),
    );

    await tester.tap(find.byKey(const Key('member-@member:example.org')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-ban')), findsOneWidget);

    await tester.tap(find.byKey(const Key('member-ban')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-moderation-confirm-Ban')));
    await tester.pumpAndSettle();

    expect(mutations.bans, <({String roomId, String userId, String? reason})>[
      (roomId: roomId, userId: member.userId, reason: null),
    ]);

    await tester.tap(find.byKey(const Key('member-@member:example.org')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-ban')), findsNothing);
    expect(find.byKey(const Key('member-kick')), findsNothing);
    expect(find.byKey(const Key('member-unban')), findsOneWidget);
    expect(find.byKey(const Key('member-role-50')), findsNothing);

    await tester.tap(find.byKey(const Key('member-unban')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-moderation-confirm-Unban')));
    await tester.pumpAndSettle();

    expect(mutations.unbans, <({String roomId, String userId})>[
      (roomId: roomId, userId: member.userId),
    ]);
  });

  testWidgets('reports a member with the optional reason preserved', (
    tester,
  ) async {
    const member = RoomMember(
      userId: '@spam:example.org',
      displayName: 'Spam account',
      membership: RoomMembership.joined,
      powerLevel: 0,
    );
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(
        directory: FakeRoomMemberDirectoryPort(
          members: const <RoomMember>[member],
        ),
        mutations: mutations,
      ),
    );

    await tester.tap(find.byKey(const Key('member-@spam:example.org')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-report')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('room-report-reason')),
      '  repeated spam  ',
    );
    await tester.tap(find.byKey(const Key('room-report-submit')));
    await tester.pumpAndSettle();

    expect(
      mutations.userReports,
      <({String roomId, String userId, String? reason})>[
        (roomId: roomId, userId: member.userId, reason: 'repeated spam'),
      ],
    );
  });

  testWidgets('room safety menu reports, leaves, and forgets explicitly', (
    tester,
  ) async {
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(
        directory: FakeRoomMemberDirectoryPort(),
        mutations: mutations,
      ),
    );

    await tester.tap(find.byKey(const Key('room-safety-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report room'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('room-report-reason')),
      '  abusive room  ',
    );
    await tester.tap(find.byKey(const Key('room-report-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-safety-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-moderation-confirm-Leave')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-safety-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove local room data'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('member-moderation-confirm-Remove data')),
    );
    await tester.pumpAndSettle();

    expect(mutations.roomReports, <({String roomId, String? reason})>[
      (roomId: roomId, reason: 'abusive room'),
    ]);
    expect(mutations.leaves, <String>[roomId]);
    expect(mutations.forgottenRooms, <String>[roomId]);
  });

  testWidgets('denied invite surfaces the SDK reason without mutating', (
    tester,
  ) async {
    final directory = FakeRoomMemberDirectoryPort();
    final authorization = FakeRoomMemberAuthorizationPort();
    authorization.decisions[RoomMemberAction.invite] =
        const RoomMemberActionAuthorization.denied(
          'Only room moderators can invite members.',
        );
    final mutations = FakeRoomMemberMutationPort();
    await pumpScreen(
      tester,
      coordinator: coordinator(
        directory: directory,
        authorization: authorization,
        mutations: mutations,
      ),
    );

    await tester.tap(find.byKey(const Key('member-invite-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('member-invite-user-id')),
      '@new:example.org',
    );
    await tester.tap(find.byKey(const Key('member-invite-submit')));
    await tester.pumpAndSettle();

    expect(mutations.invitations, isEmpty);
    expect(
      find.text('Only room moderators can invite members.'),
      findsOneWidget,
    );
  });
}
