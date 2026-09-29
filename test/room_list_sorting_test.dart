// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/utils/room_list_sorting.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  test(
    'refreshing last-event placeholders never promote stale rooms',
    () async {
      final client = await prepareTestClient();
      final recentRoom = Room(id: '!recent:test', client: client);
      final oldRoom = Room(id: '!old:test', client: client);
      final refreshingRoom = Room(id: '!refreshing:test', client: client);

      recentRoom.lastEvent = Event(
        content: const {'body': 'recent'},
        type: EventTypes.Message,
        eventId: r'$recent',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026, 9, 29, 4),
        room: recentRoom,
      );
      oldRoom.lastEvent = Event(
        content: const {'body': 'old'},
        type: EventTypes.Message,
        eventId: r'$old',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2025),
        room: oldRoom,
      );
      refreshingRoom.lastEvent = Event(
        content: const {'body': 'Refreshing last event...'},
        type: EventTypes.refreshingLastEvent,
        eventId: r'$refreshing',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026, 9, 29, 4, 30),
        room: refreshingRoom,
      );

      final rooms = [refreshingRoom, oldRoom, recentRoom]
        ..sort(compareRoomsForChatList);

      expect(rooms.map((room) => room.id), [
        '!recent:test',
        '!old:test',
        '!refreshing:test',
      ]);
      expect(roomListActivityTime(refreshingRoom), isNull);
    },
  );
  test('pinned rooms sort to the bottom', () async {
    final client = await prepareTestClient();
    final invite = Room(id: '!invite:test', client: client)
      ..membership = Membership.invite;
    final recentRoom = Room(id: '!recent:test', client: client);
    final lowPriorityRoom = Room(id: '!low:test', client: client);
    final pinnedRoom = Room(id: '!pinned:test', client: client);

    recentRoom.lastEvent = Event(
      content: const {'body': 'recent'},
      type: EventTypes.Message,
      eventId: r'$recent',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 9, 30, 1),
      room: recentRoom,
    );
    lowPriorityRoom.lastEvent = Event(
      content: const {'body': 'low'},
      type: EventTypes.Message,
      eventId: r'$low',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 9, 30, 2),
      room: lowPriorityRoom,
    );
    pinnedRoom.lastEvent = Event(
      content: const {'body': 'pinned'},
      type: EventTypes.Message,
      eventId: r'$pinned',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 9, 30, 3),
      room: pinnedRoom,
    );

    lowPriorityRoom.roomAccountData['m.tag'] = BasicEvent.fromJson({
      'content': {
        'tags': {
          'm.lowpriority': {'order': 0.1},
        },
      },
      'type': 'm.tag',
    });
    pinnedRoom.roomAccountData['m.tag'] = BasicEvent.fromJson({
      'content': {
        'tags': {
          'm.favourite': {'order': 0.1},
        },
      },
      'type': 'm.tag',
    });

    final rooms = [pinnedRoom, lowPriorityRoom, recentRoom, invite]
      ..sort(compareRoomsForChatList);

    expect(rooms.map((room) => room.id), [
      '!invite:test',
      '!recent:test',
      '!low:test',
      '!pinned:test',
    ]);
  });
}
