// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/utils/chat_list_preview_event.dart';
import 'package:matrix/matrix.dart';

import '../utils/test_client.dart';

void main() {
  test(
    'preloaded encrypted preview scroll burst stays within one frame budget',
    () async {
      final client = await prepareTestClient();
      final rooms = List.generate(80, (index) {
        final room = Room(id: '!room$index:test', client: client);
        room.lastEvent = Event(
          content: const {
            'msgtype': MessageTypes.BadEncrypted,
            'body': 'Unable to decrypt',
          },
          type: EventTypes.Encrypted,
          eventId: '\$event$index',
          senderId: '@alice:test',
          originServerTs: DateTime.utc(2026, 10, 1),
          room: room,
        );
        return room;
      });

      final preload = Stopwatch()..start();
      await preloadChatListPreviewEvents(
        rooms,
        decryptEvent: (event) async => Event(
          content: const {
            'msgtype': MessageTypes.Text,
            'body': 'Decrypted preview',
          },
          type: EventTypes.Message,
          eventId: event.eventId,
          senderId: event.senderId,
          originServerTs: event.originServerTs,
          room: event.room,
        ),
      );
      preload.stop();

      final elapsed = Stopwatch()..start();
      for (var offset = 0; offset < rooms.length; offset += 10) {
        await Future.wait(
          rooms
              .skip(offset)
              .take(10)
              .map(
                (room) => resolveChatListPreviewEvent(room, room.lastEvent!),
              ),
        );
      }
      elapsed.stop();

      final preloadUs = preload.elapsedMicroseconds;
      final scrollUs = elapsed.elapsedMicroseconds;
      final perRowUs = (scrollUs / rooms.length).round();
      debugPrint(
        'chat-list preview preload: $preloadUs us; '
        'scroll burst after preload: $scrollUs us total, $perRowUs us/row',
      );

      expect(
        elapsed.elapsedMilliseconds,
        lessThan(16),
        reason:
            'Once previews are prepared, scrolling must not spend a frame resolving subtitles.',
      );
    },
  );
}
