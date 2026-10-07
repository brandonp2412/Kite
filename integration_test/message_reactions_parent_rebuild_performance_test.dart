// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/pages/chat/events/message_reactions.dart';
import 'package:kite/widgets/matrix.dart' as kite;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/utils/test_client.dart';

const _reactionKeys = <String>['👍', '❤️', '😂', '🎉', '👀', '🔥'];

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

  testWidgets('unchanged message reactions parent rebuild performance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppSettings.init(loadWebConfigFile: false));

    final fixture = (await tester.runAsync(() async {
      final client = await prepareTestClient();
      final store = await SharedPreferences.getInstance();
      final room = Room(id: '!reactions-perf:example.invalid', client: client);
      final timeline = await room.getTimeline(limit: 0);
      final messages = <Event>[];

      for (var messageIndex = 0; messageIndex < 8; messageIndex++) {
        final message = Event(
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'Reaction benchmark message $messageIndex',
          },
          type: EventTypes.Message,
          eventId: r'$reaction-message-' + messageIndex.toString(),
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.utc(2026, 10, 7, 8, messageIndex),
          room: room,
          status: EventStatus.sent,
        );
        messages.add(message);

        final reactions = <Event>{};
        for (var reactionIndex = 0; reactionIndex < 12; reactionIndex++) {
          reactions.add(
            Event(
              content: {
                'm.relates_to': {
                  'rel_type': RelationshipTypes.reaction,
                  'event_id': message.eventId,
                  'key': _reactionKeys[reactionIndex % _reactionKeys.length],
                },
              },
              type: 'm.reaction',
              eventId: '\$reaction-$messageIndex-$reactionIndex',
              senderId: reactionIndex.isEven
                  ? (client.userID ?? '@me:example.invalid')
                  : '@reactor$reactionIndex:example.invalid',
              originServerTs: DateTime.utc(
                2026,
                10,
                7,
                8,
                messageIndex,
                reactionIndex,
              ),
              room: room,
              status: EventStatus.sent,
            ),
          );
        }
        timeline.aggregatedEvents[message.eventId] = {
          RelationshipTypes.reaction: reactions,
        };
      }

      return (
        client: client,
        store: store,
        timeline: timeline,
        messages: messages,
      );
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
                builder: (context, value, _) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in fixture.messages)
                        Padding(
                          padding: EdgeInsets.only(
                            left: value.isOdd ? 1 : 0,
                            bottom: 4,
                          ),
                          child: MessageReactions(event, fixture.timeline),
                        ),
                    ],
                  ),
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
      'fixture': 'message_reactions_parent_rebuild_v1',
      'surface': 'nox_linux',
      'messages': fixture.messages.length,
      'reactions_per_message': 12,
      'reaction_keys_per_message': _reactionKeys.length,
      'updates': 80,
    };

    await binding.watchPerformance(
      () => _pumpParentUpdates(tester, tick),
      reportKey: 'message_reactions_parent_rebuild',
    );

    final firstMessage = fixture.messages.first;
    final firstMessageReactions = firstMessage.aggregatedEvents(
      fixture.timeline,
      RelationshipTypes.reaction,
    );
    firstMessageReactions.add(
      Event(
        content: {
          'm.relates_to': {
            'rel_type': RelationshipTypes.reaction,
            'event_id': firstMessage.eventId,
            'key': _reactionKeys.first,
          },
        },
        type: 'm.reaction',
        eventId: r'$reaction-correctness-mutation',
        senderId: fixture.client.userID ?? '@me:example.invalid',
        originServerTs: DateTime.utc(2026, 10, 7, 9),
        room: firstMessage.room,
        status: EventStatus.sent,
      ),
    );
    tick.value++;
    await tester.pumpAndSettle();

    final firstReactionWidget = find.byWidgetPredicate(
      (widget) =>
          widget is MessageReactions && identical(widget.event, firstMessage),
    );
    expect(
      find.descendant(of: firstReactionWidget, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstReactionWidget, matching: find.text('2')),
      findsNWidgets(_reactionKeys.length - 1),
    );
  });
}
