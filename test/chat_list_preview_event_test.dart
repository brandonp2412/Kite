// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/utils/chat_list_preview_event.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  test('uses a decrypted cached event for an encrypted room preview', () async {
    final client = await prepareTestClient();
    final room = Room(id: '!room:test', client: client);
    final encryptedLastEvent = Event(
      content: const {
        'msgtype': MessageTypes.BadEncrypted,
        'body': 'Unable to decrypt',
      },
      type: EventTypes.Encrypted,
      eventId: r'$event',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 10, 1),
      room: room,
    );
    final decryptedEvent = Event(
      content: const {'msgtype': MessageTypes.Text, 'body': 'Cached message'},
      type: EventTypes.Message,
      eventId: r'$event',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 10, 1),
      room: room,
    );
    room.lastEvent = encryptedLastEvent;

    await client.database.transaction(() async {
      await client.database.storeEventUpdate(
        room.id,
        decryptedEvent,
        EventUpdateType.timeline,
        client,
      );
    });

    final previewEvent = await resolveChatListPreviewEvent(
      room,
      encryptedLastEvent,
    );

    expect(previewEvent.type, EventTypes.Message);
    expect(previewEvent.content['body'], 'Cached message');
    expect(room.lastEvent?.type, EventTypes.Message);
    expect(room.lastEvent?.content['body'], 'Cached message');
  });

  test(
    'decrypts the preview when only the encrypted event is cached',
    () async {
      final client = await prepareTestClient();
      final room = Room(id: '!room:test', client: client);
      final encryptedLastEvent = Event(
        content: const {
          'msgtype': MessageTypes.BadEncrypted,
          'body': 'Unable to decrypt',
        },
        type: EventTypes.Encrypted,
        eventId: r'$decrypt',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026, 10, 1),
        room: room,
      );
      final decryptedEvent = Event(
        content: const {'msgtype': MessageTypes.Text, 'body': 'Decrypted now'},
        type: EventTypes.Message,
        eventId: r'$decrypt',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026, 10, 1),
        room: room,
      );
      room.lastEvent = encryptedLastEvent;

      await client.database.transaction(() async {
        await client.database.storeEventUpdate(
          room.id,
          encryptedLastEvent,
          EventUpdateType.timeline,
          client,
        );
      });

      var decryptCalls = 0;
      final previewEvent = await resolveChatListPreviewEvent(
        room,
        encryptedLastEvent,
        decryptEvent: (event) async {
          decryptCalls++;
          expect(identical(event, encryptedLastEvent), isTrue);
          return decryptedEvent;
        },
      );

      expect(decryptCalls, 1);
      expect(previewEvent.content['body'], 'Decrypted now');
      expect(room.lastEvent?.content['body'], 'Decrypted now');
    },
  );

  test('deduplicates in-flight preview decryption', () async {
    final client = await prepareTestClient();
    final room = Room(id: '!room:test', client: client);
    final encryptedLastEvent = Event(
      content: const {
        'msgtype': MessageTypes.BadEncrypted,
        'body': 'Unable to decrypt',
      },
      type: EventTypes.Encrypted,
      eventId: r'$dedupe',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 10, 1),
      room: room,
    );
    final decryptedEvent = Event(
      content: const {'msgtype': MessageTypes.Text, 'body': 'Resolved once'},
      type: EventTypes.Message,
      eventId: r'$dedupe',
      senderId: '@alice:test',
      originServerTs: DateTime.utc(2026, 10, 1),
      room: room,
    );
    room.lastEvent = encryptedLastEvent;

    final completer = Completer<Event>();
    var decryptCalls = 0;
    Future<Event> decrypt(Event event) {
      decryptCalls++;
      return completer.future;
    }

    final first = resolveChatListPreviewEvent(
      room,
      encryptedLastEvent,
      decryptEvent: decrypt,
    );
    final second = resolveChatListPreviewEvent(
      room,
      encryptedLastEvent,
      decryptEvent: decrypt,
    );

    await Future<void>.delayed(Duration.zero);
    expect(decryptCalls, 1);
    completer.complete(decryptedEvent);

    final results = await Future.wait([first, second]);
    expect(
      results.every((event) => event.content['body'] == 'Resolved once'),
      isTrue,
    );
    expect(decryptCalls, 1);
  });

  test(
    'keeps the encrypted event when no decrypted cache entry exists',
    () async {
      final client = await prepareTestClient();
      final room = Room(id: '!room:test', client: client);
      final encryptedLastEvent = Event(
        content: const {
          'msgtype': MessageTypes.BadEncrypted,
          'body': 'Unable to decrypt',
        },
        type: EventTypes.Encrypted,
        eventId: r'$missing',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026, 10, 1),
        room: room,
      );
      room.lastEvent = encryptedLastEvent;

      final previewEvent = await resolveChatListPreviewEvent(
        room,
        encryptedLastEvent,
      );

      expect(identical(previewEvent, encryptedLastEvent), isTrue);
      expect(identical(room.lastEvent, encryptedLastEvent), isTrue);
    },
  );
}
