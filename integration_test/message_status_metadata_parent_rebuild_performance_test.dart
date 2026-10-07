// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/pages/chat/events/message.dart';
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

  testWidgets('unchanged send status metadata parent rebuild performance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    await tester.runAsync(() => AppSettings.init(loadWebConfigFile: false));

    final fixture = (await tester.runAsync(() async {
      final client = await prepareTestClient();
      final store = await SharedPreferences.getInstance();
      final room = Room(
        id: '!status-metadata-perf:example.invalid',
        client: client,
      );
      final timeline = await room.getTimeline(limit: 0);
      final senderId = client.userID ?? '@status-author:example.invalid';

      room.setState(
        Event(
          content: const {'membership': 'join', 'displayname': 'Status Author'},
          type: EventTypes.RoomMember,
          stateKey: senderId,
          eventId: r'$status-author-member',
          senderId: senderId,
          originServerTs: DateTime.utc(2026, 10, 8, 3, 45),
          room: room,
          status: EventStatus.sent,
        ),
      );

      final messages = <Event>[
        for (var messageIndex = 0; messageIndex < 8; messageIndex++)
          Event(
            content: {
              'msgtype': MessageTypes.Text,
              'body': 'Status metadata benchmark message $messageIndex',
            },
            type: EventTypes.Message,
            eventId: r'$status-metadata-root-' + messageIndex.toString(),
            senderId: senderId,
            originServerTs: DateTime.utc(2026, 10, 8, 3, 46, messageIndex),
            room: room,
            status: EventStatus.error,
          ),
      ];

      return (
        client: client,
        store: store,
        timeline: timeline,
        messages: messages,
      );
    }))!;

    addTearDown(fixture.client.dispose);

    final tick = ValueNotifier<int>(0);
    final scrollController = ScrollController();
    addTearDown(tick.dispose);
    addTearDown(scrollController.dispose);

    void enterThread(String eventId) {}

    await tester.pumpWidget(
      kite.Matrix(
        clients: [fixture.client],
        store: fixture.store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [
            ...L10n.localizationsDelegates,
            ...GlobalMaterialLocalizations.delegates,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, value, _) => SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in fixture.messages)
                        Padding(
                          padding: EdgeInsets.only(
                            left: value.isOdd ? 1 : 0,
                            bottom: 4,
                          ),
                          child: Message(
                            event,
                            bigEmojis: const <String>{},
                            onSelect: (_) {},
                            onInfoTab: (_) {},
                            scrollToEventId: (_) {},
                            onSwipe: () {},
                            onEdit: () {},
                            singleSelected: false,
                            timeline: fixture.timeline,
                            onMention: () {},
                            scrollController: scrollController,
                            colors: const <Color>[Colors.blue, Colors.purple],
                            enterThread: enterThread,
                          ),
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
      'fixture': 'message_status_metadata_parent_rebuild_v1',
      'surface': 'nox_linux',
      'messages': fixture.messages.length,
      'updates': 80,
      'status': 'error',
    };

    await binding.watchPerformance(
      () => _pumpParentUpdates(tester, tick),
      reportKey: 'message_status_metadata_parent_rebuild',
    );

    final firstMessage = fixture.messages.first;
    final firstMessageFinder = find.byWidgetPredicate(
      (widget) => widget is Message && identical(widget.event, firstMessage),
    );
    expect(firstMessageFinder, findsOneWidget);

    Finder errorLabel() => find.descendant(
      of: firstMessageFinder,
      matching: find.text('Could not be sent'),
    );

    expect(errorLabel(), findsOneWidget);
    firstMessage.status = EventStatus.sent;
    tick.value++;
    await tester.pumpAndSettle();
    expect(errorLabel(), findsNothing);
  });
}
