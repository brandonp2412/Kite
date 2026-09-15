import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

final class _FailingRoomMemberDirectoryPort implements RoomMemberDirectoryPort {
  const _FailingRoomMemberDirectoryPort();

  @override
  Future<RoomPowerLevelSummary> powerLevels(String roomId) async =>
      throw StateError('deterministic directory failure');

  @override
  Future<List<RoomMember>> searchMembers({
    required String roomId,
    required String query,
  }) async => throw StateError('deterministic directory failure');
}

void main() {
  Future<void> pumpMembers(
    WidgetTester tester, {
    required ThemeMode themeMode,
    RoomMemberDirectoryPort? directory,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final coordinator = RoomMemberManagementCoordinator(
      actorUserId: '@moderator:example.org',
      directory:
          directory ??
          FakeRoomMemberDirectoryPort(
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

    final content = find.byKey(const Key('member-content'));
    expect(tester.getSize(content).width, KiteLayout.readableContentMaxWidth);
    expect(tester.getTopLeft(content).dx, 240);

    await expectLater(
      find.byType(RoomMembersScreen),
      matchesGoldenFile('goldens/room_members_light.png'),
    );
  });

  testWidgets('approved room members baseline - dark', (tester) async {
    await pumpMembers(tester, themeMode: ThemeMode.dark);

    final content = find.byKey(const Key('member-content'));
    expect(tester.getSize(content).width, KiteLayout.readableContentMaxWidth);
    expect(tester.getTopLeft(content).dx, 240);

    await expectLater(
      find.byType(RoomMembersScreen),
      matchesGoldenFile('goldens/room_members_dark.png'),
    );
  });

  for (final variant in <({String name, ThemeMode mode})>[
    (name: 'light', mode: ThemeMode.light),
    (name: 'dark', mode: ThemeMode.dark),
  ]) {
    testWidgets('room members empty state - ${variant.name}', (tester) async {
      await pumpMembers(
        tester,
        themeMode: variant.mode,
        directory: FakeRoomMemberDirectoryPort(),
      );

      expect(find.text('No members found'), findsOneWidget);
      expect(find.byKey(const Key('member-list')), findsNothing);
      await expectLater(
        find.byType(RoomMembersScreen),
        matchesGoldenFile('goldens/room_members_empty_${variant.name}.png'),
      );
    });

    testWidgets('room members error state - ${variant.name}', (tester) async {
      await pumpMembers(
        tester,
        themeMode: variant.mode,
        directory: const _FailingRoomMemberDirectoryPort(),
      );

      expect(find.text('Kite could not load room members.'), findsOneWidget);
      expect(find.text('Could not load members'), findsOneWidget);
      expect(find.byKey(const Key('member-load-retry')), findsOneWidget);
      expect(find.text('No members found'), findsNothing);
      await expectLater(
        find.byType(RoomMembersScreen),
        matchesGoldenFile('goldens/room_members_error_${variant.name}.png'),
      );
    });
  }
}
