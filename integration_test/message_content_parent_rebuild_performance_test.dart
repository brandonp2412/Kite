// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/pages/chat/events/message_content.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/utils/test_client.dart';

const _fixtureHtml = '''
<p><strong>Release status:</strong> the renderer keeps <em>formatted text</em>,
<a href="https://example.invalid/docs">linked documentation</a>, and nested
<span data-mx-color="#336699">styled spans</span> visible.</p>
<ul><li>First deterministic item</li><li>Second deterministic item</li></ul>
<blockquote>Repeated parent state updates should not rebuild unchanged content.</blockquote>
<p>Inline <code>final answer = 42;</code> keeps syntax work in the fixture.</p>
''';

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

  testWidgets('unchanged message content parent rebuild performance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppSettings.init(loadWebConfigFile: false));

    final fixture = (await tester.runAsync(() async {
      final client = await prepareTestClient();
      final room = Room(id: '!content-perf:example.invalid', client: client);
      final timeline = await room.getTimeline(limit: 0);
      final events = List.generate(
        8,
        (index) => Event(
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'Release status item $index',
            'format': 'org.matrix.custom.html',
            'formatted_body': '$_fixtureHtml<p>Message $index</p>',
          },
          type: EventTypes.Message,
          eventId: '\$content$index',
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.utc(2026, 10, 7, 5, index),
          room: room,
          status: EventStatus.sent,
        ),
      );
      return (client: client, room: room, timeline: timeline, events: events);
    }))!;
    addTearDown(fixture.client.dispose);

    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: ValueListenableBuilder<int>(
              valueListenable: tick,
              builder: (context, value, _) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final event in fixture.events)
                      MessageContent(
                        event,
                        timeline: fixture.timeline,
                        textColor: Colors.black87,
                        linkColor: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                        selected: value.isOdd,
                        bigEmojis: const <String>{},
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

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['metadata'] = <String, dynamic>{
      'fixture': 'message_content_parent_rebuild_v1',
      'surface': 'nox_linux',
      'messages': fixture.events.length,
      'updates': 80,
    };

    await binding.watchPerformance(
      () => _pumpParentUpdates(tester, tick),
      reportKey: 'message_content_parent_rebuild',
    );
  });
}
