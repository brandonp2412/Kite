// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/pages/chat/seen_by_row.dart';
import 'package:kite/widgets/avatar.dart';
import 'package:kite/widgets/matrix.dart' as kite;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/utils/test_client.dart';

Future<void> _pumpParentUpdates(
  WidgetTester tester,
  ValueNotifier<int> tick,
) async {
  for (var index = 0; index < 80; index++) {
    tick.value++;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unchanged read receipts parent rebuild performance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppSettings.init(loadWebConfigFile: false));

    final fixture = (await tester.runAsync(() async {
      final client = await prepareTestClient();
      final store = await SharedPreferences.getInstance();
      final rooms = <Room>[];
      final events = <Event>[];

      for (var roomIndex = 0; roomIndex < 8; roomIndex++) {
        final room = Room(
          id: '!seen-by-perf-$roomIndex:example.invalid',
          client: client,
        );
        final event = Event(
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'Read receipt benchmark message $roomIndex',
          },
          type: EventTypes.Message,
          eventId: '\$seen-by-event-$roomIndex',
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.utc(2026, 10, 8, 1, roomIndex),
          room: room,
          status: EventStatus.sent,
        );

        for (var readerIndex = 0; readerIndex < 12; readerIndex++) {
          final userId = '@reader-$roomIndex-$readerIndex:example.invalid';
          room.setState(
            Event(
              content: {
                'membership': 'join',
                'displayname': 'Reader $roomIndex $readerIndex',
              },
              type: EventTypes.RoomMember,
              stateKey: userId,
              eventId: '\$member-$roomIndex-$readerIndex',
              senderId: userId,
              originServerTs: DateTime.utc(
                2026,
                10,
                8,
                1,
                roomIndex,
                readerIndex,
              ),
              room: room,
              status: EventStatus.sent,
            ),
          );
          room.receiptState.global.otherUsers[userId] = LatestReceiptStateData(
            event.eventId,
            DateTime.utc(
              2026,
              10,
              8,
              1,
              roomIndex,
              readerIndex,
            ).millisecondsSinceEpoch,
          );
        }

        rooms.add(room);
        events.add(event);
      }

      return (client: client, store: store, rooms: rooms, events: events);
    }))!;
    addTearDown(fixture.client.dispose);

    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);

    await tester.pumpWidget(
      kite.Matrix(
        clients: [fixture.client],
        store: fixture.store,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, value, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final event in fixture.events)
                      Padding(
                        padding: EdgeInsets.only(
                          left: value.isOdd ? 1 : 0,
                          bottom: 4,
                        ),
                        child: SeenByRow(event: event),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Avatar), findsNWidgets(8 * 7));
    expect(find.text('+5'), findsNWidgets(8));

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['metadata'] = <String, dynamic>{
      'fixture': 'seen_by_row_parent_rebuild_v1',
      'surface': 'nox_linux',
      'rows': fixture.events.length,
      'receipts_per_row': 12,
      'visible_avatars_per_row': 7,
      'updates': 80,
    };

    await binding.watchPerformance(
      () => _pumpParentUpdates(tester, tick),
      reportKey: 'seen_by_row_parent_rebuild',
    );

    final firstRoom = fixture.rooms.first;
    const replacementUserId = '@replacement-reader:example.invalid';
    firstRoom.setState(
      Event(
        content: const {
          'membership': 'join',
          'displayname': 'Replacement Reader',
        },
        type: EventTypes.RoomMember,
        stateKey: replacementUserId,
        eventId: r'$replacement-member',
        senderId: replacementUserId,
        originServerTs: DateTime.utc(2026, 10, 8, 2),
        room: firstRoom,
        status: EventStatus.sent,
      ),
    );
    firstRoom.receiptState.global.otherUsers
      ..clear()
      ..[replacementUserId] = LatestReceiptStateData(
        fixture.events.first.eventId,
        DateTime.utc(2026, 10, 8, 2).millisecondsSinceEpoch,
      );
    tick.value++;
    await tester.pumpAndSettle();

    expect(find.byType(Avatar), findsNWidgets((7 * 7) + 1));
    expect(find.text('+5'), findsNWidgets(7));
  });
}
