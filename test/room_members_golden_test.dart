import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

void main() {
  Future<void> pumpMembers(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@moderator:example.org',
      directory: FakeRoomMemberDirectoryPort(
        members: const <RoomMember>[
          RoomMember(
            userId: '@moderator:example.org',
            displayName: 'Morgan',
            membership: RoomMembership.joined,
            powerLevel: 50,
          ),
          RoomMember(
            userId: '@alice:example.org',
            displayName: 'Alice',
            membership: RoomMembership.joined,
            powerLevel: 0,
          ),
          RoomMember(
            userId: '@owner:example.org',
            displayName: 'Sam',
            membership: RoomMembership.joined,
            powerLevel: 100,
          ),
        ],
      ),
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: RoomMembersScreen(
          roomId: '!team:example.org',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('approved room members baseline - light', (tester) async {
    await pumpMembers(tester, themeMode: ThemeMode.light);

    await expectLater(
      find.byType(RoomMembersScreen),
      matchesGoldenFile('goldens/room_members_light.png'),
    );
  });

  testWidgets('approved room members baseline - dark', (tester) async {
    await pumpMembers(tester, themeMode: ThemeMode.dark);

    await expectLater(
      find.byType(RoomMembersScreen),
      matchesGoldenFile('goldens/room_members_dark.png'),
    );
  });
}
