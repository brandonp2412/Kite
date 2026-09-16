import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

void main() {
  test('cached Matrix state replaces fixture room and timeline defaults', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!real:example.org',
            displayName: 'Real room',
            lastActivity: DateTime.utc(2026, 9, 16, 11),
            streamPosition: 1,
            lastEventId: r'$cached',
            unreadCount: 2,
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!real:example.org': <MatrixTimelineEvent>[
            _event(
              eventId: r'$cached',
              body: 'Cached before sync',
              streamPosition: 1,
            ),
          ],
        },
      ),
    );
    final selectedRoom = signal('kite');
    final controller = TimelineController();
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: selectedRoom,
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    expect(binding.roomListStore.roomIds, <String>['!real:example.org']);
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.name,
      'Real room',
    );
    expect(selectedRoom.value, '!real:example.org');
    expect(
      controller.messagesFor('!real:example.org').value.single.body,
      'Cached before sync',
    );
    expect(controller.messagesFor('kite').value, isEmpty);
  });

  test('incremental cache updates reconcile rooms and timelines', () async {
    final cache = MatrixPresentationCache();
    final controller = TimelineController();
    final selectedRoom = signal('missing');
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: selectedRoom,
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!real:example.org',
            summary: MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Synced room',
              lastActivity: DateTime.utc(2026, 9, 16, 11, 10),
              streamPosition: 1,
              lastEventId: r'$one',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(eventId: r'$one', body: 'One', streamPosition: 1),
            ],
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(binding.roomListStore.roomIds, <String>['!real:example.org']);
    expect(selectedRoom.value, '!real:example.org');
    expect(
      controller.messagesFor('!real:example.org').value.single.body,
      'One',
    );

    cache.applySync(
      MatrixSyncBatch(
        cursor: 's2',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!real:example.org',
            summary: MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Synced room renamed',
              lastActivity: DateTime.utc(2026, 9, 16, 11, 11),
              streamPosition: 2,
              lastEventId: r'$two',
              unreadCount: 3,
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(eventId: r'$two', body: 'Two', streamPosition: 2),
            ],
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final room = binding.roomListStore.roomSignal('!real:example.org').value;
    expect(room.name, 'Synced room renamed');
    expect(room.latestEventBody, 'Two');
    expect(room.unreadCount, 3);
    expect(
      controller
          .messagesFor('!real:example.org')
          .value
          .map((message) => message.body),
      <String>['One', 'Two'],
    );
  });

  testWidgets(
    'Matrix home composer sends through its production timeline port',
    (tester) async {
      final calls = <String>[];
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Real room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              lastEventId: r'$cached',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!real:example.org': <MatrixTimelineEvent>[
              _event(
                eventId: r'$cached',
                body: 'Cached before send',
                streamPosition: 1,
              ),
            ],
          },
        ),
      );

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              calls.add('$roomId|$transactionId|$body');
            }),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Real room'), findsWidgets);
      expect(find.text('Cached before send'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'From production composer',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(
        calls.single,
        startsWith('!real:example.org|kite-local-0|From production composer'),
      );
      expect(find.text('From production composer'), findsOneWidget);
    },
  );

  testWidgets(
    'compact Matrix timeline keeps the production send port after navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final calls = <String>[];
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!mobile:example.org',
              displayName: 'Mobile room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              lastEventId: r'$mobile',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!mobile:example.org': <MatrixTimelineEvent>[
              MatrixTimelineEvent(
                eventId: r'$mobile',
                roomId: '!mobile:example.org',
                senderId: '@alice:example.org',
                type: 'm.room.message',
                originServerTimestamp: DateTime.utc(2026, 9, 16, 11),
                streamPosition: 1,
                content: const <String, Object?>{
                  'msgtype': 'm.text',
                  'body': 'Cached mobile message',
                },
              ),
            ],
          },
        ),
      );

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              calls.add('$roomId|$transactionId|$body');
            }),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('room-!mobile:example.org')));
      await tester.pumpAndSettle();
      expect(find.text('Cached mobile message'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'From compact composer',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(
        calls.single,
        startsWith('!mobile:example.org|kite-local-0|From compact composer'),
      );
    },
  );

  test(
    'production send port settles optimistic messages from real sender',
    () async {
      final calls = <String>[];
      var fail = false;
      final port = MatrixTimelineSendPort(({
        required roomId,
        required transactionId,
        required body,
      }) async {
        calls.add('$roomId|$transactionId|$body');
        if (fail) throw StateError('network failure');
      });
      final controller = TimelineController(
        sendPort: port,
        fixtureProvider: (_) => const [],
      );

      final sent = controller.sendText('!room:example.org', 'Sent');
      await Future<void>.delayed(Duration.zero);
      expect(sent.sendState.value, TimelineSendState.sent);
      expect(calls.single, startsWith('!room:example.org|kite-local-0|Sent'));

      fail = true;
      final failed = controller.sendText('!room:example.org', 'Failed');
      await Future<void>.delayed(Duration.zero);
      expect(failed.sendState.value, TimelineSendState.failed);
    },
  );
}

MatrixTimelineEvent _event({
  required String eventId,
  required String body,
  required int streamPosition,
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: '!real:example.org',
    senderId: '@alice:example.org',
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 16, 11, streamPosition),
    streamPosition: streamPosition,
    content: <String, Object?>{'msgtype': 'm.text', 'body': body},
  );
}
