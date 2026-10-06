// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/pages/chat/events/html_message.dart';
import 'package:kite/pages/chat/events/message_content.dart';
import 'package:kite/utils/event_checkbox_extension.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  testWidgets('cached HTML content refreshes when rendered inputs change', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppSettings.init(loadWebConfigFile: false));

    final fixture = (await tester.runAsync(() async {
      final client = await prepareTestClient();
      final room = Room(id: '!content-cache:example.invalid', client: client);
      final timeline = await room.getTimeline(limit: 0);
      return (client: client, room: room, timeline: timeline);
    }))!;
    addTearDown(fixture.client.dispose);

    Event message(String formattedBody) => Event(
      content: {
        'msgtype': MessageTypes.Text,
        'body': 'Task',
        'format': 'org.matrix.custom.html',
        'formatted_body': formattedBody,
      },
      type: EventTypes.Message,
      eventId: r'$message',
      senderId: '@alice:example.invalid',
      originServerTs: DateTime.utc(2026, 10, 7),
      room: fixture.room,
      status: EventStatus.sent,
    );

    var event = message(
      '<ul><li class="task-list-item"><input type="checkbox">First</li></ul>',
    );

    Widget app(Color textColor, Color linkColor) => MaterialApp(
      home: Scaffold(
        body: MessageContent(
          event,
          timeline: fixture.timeline,
          textColor: textColor,
          linkColor: linkColor,
          borderRadius: BorderRadius.circular(12),
          selected: false,
          bigEmojis: const <String>{},
        ),
      ),
    );

    await tester.pumpWidget(app(Colors.black, Colors.blue));
    await tester.pump();

    var html = tester.widget<HtmlMessage>(find.byType(HtmlMessage));
    expect(html.html, contains('First'));
    expect(html.textColor, Colors.black);
    expect(html.linkStyle.color, Colors.blue);
    expect(
      tester.widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox)).value,
      isFalse,
    );

    event = message(
      '<ul><li class="task-list-item"><input type="checkbox">Second</li></ul>',
    );
    await tester.pumpWidget(app(Colors.purple, Colors.orange));
    await tester.pump();

    html = tester.widget<HtmlMessage>(find.byType(HtmlMessage));
    expect(html.html, contains('Second'));
    expect(html.textColor, Colors.purple);
    expect(html.linkStyle.color, Colors.orange);

    final checkboxEvent = Event(
      content: {
        'm.relates_to': {
          'rel_type': EventCheckboxRoomExtension.relationshipType,
          'event_id': event.eventId,
          'checkbox_id': 1,
        },
      },
      type: EventTypes.Reaction,
      eventId: r'$checkbox',
      senderId: '@alice:example.invalid',
      originServerTs: DateTime.utc(2026, 10, 7, 0, 1),
      room: fixture.room,
      status: EventStatus.sent,
    );
    fixture.timeline.aggregatedEvents[event.eventId] = {
      EventCheckboxRoomExtension.relationshipType: {checkboxEvent},
    };

    await tester.pumpWidget(app(Colors.purple, Colors.orange));
    await tester.pump();

    expect(
      tester.widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox)).value,
      isTrue,
    );
  });
}
