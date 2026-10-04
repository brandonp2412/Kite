// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/l10n/l10n_de.dart';
import 'package:kite/l10n/l10n_en.dart';
import 'package:kite/utils/chat_list_preview_text.dart';
import 'package:kite/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

class _CountingEvent extends Event {
  _CountingEvent(Room room)
    : super(
        room: room,
        type: EventTypes.Message,
        eventId: r'$preview',
        senderId: '@alice:test',
        originServerTs: DateTime.utc(2026),
        content: {'msgtype': MessageTypes.Text, 'body': '**Hello**'},
      );

  int formats = 0;

  @override
  String calcUnlocalizedBody({
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    formats++;
    return super.calcUnlocalizedBody(
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
  }
}

void main() {
  test(
    'repeated previews avoid parsing and edits invalidate cached text',
    () async {
      final room = Room(id: '!room:test', client: await prepareTestClient());
      final event = _CountingEvent(room);
      room.setState(User('@alice:test', room: room, displayName: 'Alice'));
      final locals = MatrixLocals(L10nEn());
      String preview() =>
          chatListPreviewText(event, locals, withSenderNamePrefix: false);

      for (var i = 0; i < 100; i++) {
        expect(preview(), 'Hello');
      }
      expect(event.formats, 1);

      event.content['body'] = '**Edited**';
      expect(preview(), 'Edited');
      expect(event.formats, 2);

      event.setRedactionEvent(
        Event(
          room: room,
          type: EventTypes.Redaction,
          eventId: r'$redaction',
          senderId: '@alice:test',
          originServerTs: DateTime.utc(2026),
          content: {},
        ),
      );
      expect(preview(), isNot(contains('Edited')));
      expect(
        preview(),
        event.calcLocalizedBodyFallback(
          locals,
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
          removeMarkdown: true,
        ),
      );
    },
  );

  test('sender names, prefix and locale stay current', () async {
    final room = Room(id: '!room:test', client: await prepareTestClient());
    final event = _CountingEvent(room);
    final english = MatrixLocals(L10nEn());
    room.setState(User('@alice:test', room: room, displayName: 'Alice'));
    expect(
      chatListPreviewText(event, english, withSenderNamePrefix: true),
      'Alice: Hello',
    );
    room.setState(User('@alice:test', room: room, displayName: 'Alicia'));
    expect(
      chatListPreviewText(event, english, withSenderNamePrefix: true),
      'Alicia: Hello',
    );
    expect(
      chatListPreviewText(event, english, withSenderNamePrefix: false),
      'Hello',
    );
    chatListPreviewText(
      event,
      MatrixLocals(L10nDe()),
      withSenderNamePrefix: false,
    );
    expect(event.formats, 4);

    event.type = EventTypes.RoomName;
    event.content = {'name': 'New room name'};
    final stateText = chatListPreviewText(
      event,
      english,
      withSenderNamePrefix: false,
    );
    expect(stateText, 'Alicia changed the chat name');
    expect(event.formats, 5);
  });
}
