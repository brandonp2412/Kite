import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/rooms/room_directory_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';

void main() {
  testWidgets('searches the Matrix public-room directory with metadata', (
    tester,
  ) async {
    final rooms = DeterministicRoomManagementPort(
      roomDirectoryResults: const <KiteRoomDirectoryResult>[
        KiteRoomDirectoryResult(
          roomId: '!kite:example.org',
          name: 'Kite Community',
          topic: 'Flutter Matrix client',
          canonicalAlias: '#kite:example.org',
          avatarUrl: null,
          joinRule: 'public',
          worldReadable: true,
          joinedMembers: 1234,
        ),
      ],
    );
    final coordinator = RoomManagementCoordinator(
      rooms: rooms,
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomDirectoryScreen(
          coordinator: coordinator,
          initialQuery: 'kite',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kite Community'), findsOneWidget);
    expect(find.text('#kite:example.org'), findsOneWidget);
    expect(find.text('Flutter Matrix client'), findsOneWidget);
    expect(find.text('1,234 members • Public'), findsOneWidget);
    expect(
      rooms.invocations
          .where(
            (entry) =>
                entry.type == RoomManagementInvocationType.searchRoomDirectory,
          )
          .single
          .text,
      'kite',
    );

    await tester.enterText(
      find.byKey(const Key('room-directory-search')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 181));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-directory-empty')), findsOneWidget);
  });
}
