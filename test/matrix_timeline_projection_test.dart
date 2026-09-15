import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  test(
    'Matrix room projection exposes latest sender, preview and unread count',
    () {
      final cache = MatrixPresentationCache();
      cache.applySync(
        MatrixSyncBatch(
          cursor: 's1',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:example.org',
              summary: MatrixRoomSummary(
                roomId: '!alpha:example.org',
                displayName: 'Alpha',
                lastActivity: DateTime.utc(2026, 9, 16, 10, 30),
                streamPosition: 1,
                lastEventId: r'$one',
                unreadCount: 3,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                _event(
                  eventId: r'$one',
                  streamPosition: 1,
                  senderId: '@alice:example.org',
                  msgtype: 'm.text',
                  body: 'Synced from Matrix',
                ),
              ],
            ),
          ],
        ),
      );

      final entries = matrixRoomListEntries(cache);

      expect(entries, hasLength(1));
      expect(entries.single.id, '!alpha:example.org');
      expect(entries.single.name, 'Alpha');
      expect(entries.single.latestSender, '@alice:example.org');
      expect(entries.single.latestEventBody, 'Synced from Matrix');
      expect(entries.single.unreadCount, 3);
    },
  );

  test(
    'room reconciliation keeps existing leaf signals while order changes',
    () {
      const alpha = RoomListEntry(
        id: '!alpha:example.org',
        name: 'Alpha',
        latestEventBody: 'Old',
      );
      const beta = RoomListEntry(
        id: '!beta:example.org',
        name: 'Beta',
        latestEventBody: 'Beta event',
      );
      final store = RoomListStateStore(const <RoomListEntry>[alpha, beta]);
      final alphaSignal = store.roomSignal(alpha.id);

      store.reconcile(<RoomListEntry>[
        beta,
        alpha.copyWith(latestEventBody: 'New', unreadCount: 4),
      ]);

      expect(store.roomIds, <String>[beta.id, alpha.id]);
      expect(store.visibleRoomIds.value, <String>[beta.id, alpha.id]);
      expect(store.roomSignal(alpha.id), same(alphaSignal));
      expect(alphaSignal.value.latestEventBody, 'New');
      expect(alphaSignal.value.unreadCount, 4);
    },
  );

  test(
    'Matrix message projection covers text, audio, voice and MIDI events',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final events = <MatrixTimelineEvent>[
        _event(
          eventId: r'$text',
          streamPosition: 1,
          senderId: '@alice:example.org',
          msgtype: 'm.text',
          body: 'Hello from sync',
        ),
        _event(
          eventId: r'$audio',
          streamPosition: 2,
          senderId: '@alice:example.org',
          msgtype: 'm.audio',
          body: 'song.m4a',
          info: const <String, Object?>{
            'size': 2200000,
            'duration': 65000,
            'mimetype': 'audio/mp4',
          },
        ),
        _event(
          eventId: r'$voice',
          streamPosition: 3,
          senderId: '@me:example.org',
          msgtype: 'm.audio',
          body: 'voice.ogg',
          info: const <String, Object?>{
            'size': 268000,
            'duration': 12000,
            'mimetype': 'audio/ogg',
          },
          extra: const <String, Object?>{
            'org.matrix.msc3245.voice': <String, Object?>{},
          },
        ),
        _event(
          eventId: r'$midi',
          streamPosition: 4,
          senderId: '@alice:example.org',
          msgtype: 'm.file',
          body: 'theme.mid',
          info: const <String, Object?>{'size': 4096, 'mimetype': 'audio/midi'},
        ),
      ];

      controller.applyMatrixEvents(
        '!alpha:example.org',
        events,
        currentUserId: '@me:example.org',
      );
      final messages = controller.messagesFor('!alpha:example.org').value;

      expect(messages, hasLength(4));
      expect(messages[0].body, 'Hello from sync');
      expect(messages[1].attachment?.kind, TimelineAttachmentKind.audio);
      expect(messages[1].attachment?.durationLabel, '1:05');
      expect(messages[2].attachment?.kind, TimelineAttachmentKind.voice);
      expect(messages[2].mine, isTrue);
      expect(messages[3].attachment?.kind, TimelineAttachmentKind.audio);
      expect(messages[3].attachment?.name, 'theme.mid');
    },
  );

  test('Matrix transaction IDs reconcile optimistic local sends', () async {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
    controller.applyMatrixEvents(
      '!alpha:example.org',
      const <MatrixTimelineEvent>[],
      currentUserId: '@me:example.org',
    );
    final local = controller.sendText('!alpha:example.org', 'Sent for real');
    await Future<void>.delayed(Duration.zero);

    controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
      _event(
        eventId: r'$real',
        streamPosition: 9,
        senderId: '@me:example.org',
        msgtype: 'm.text',
        body: 'Sent for real',
        transactionId: local.id,
      ),
    ], currentUserId: '@me:example.org');

    final messages = controller.messagesFor('!alpha:example.org').value;
    expect(messages, hasLength(1));
    expect(messages.single.id, r'$real');
    expect(messages.single.sendState.value, TimelineSendState.sent);
  });

  test(
    'incremental Matrix projection preserves old identity and local sends',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final first = _event(
        eventId: r'$first',
        streamPosition: 1,
        senderId: '@alice:example.org',
        msgtype: 'm.text',
        body: 'First',
      );
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        first,
      ], currentUserId: '@me:example.org');
      final firstMessage = controller
          .messagesFor('!alpha:example.org')
          .value
          .single;
      final local = controller.sendText('!alpha:example.org', 'Queued locally');
      final second = _event(
        eventId: r'$second',
        streamPosition: 2,
        senderId: '@bob:example.org',
        msgtype: 'm.text',
        body: 'Second',
      );

      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        first,
        second,
      ], currentUserId: '@me:example.org');
      final messages = controller.messagesFor('!alpha:example.org').value;

      expect(messages, hasLength(3));
      expect(messages[0], same(firstMessage));
      expect(messages[1].id, r'$second');
      expect(messages[2], same(local));
    },
  );
}

MatrixTimelineEvent _event({
  required String eventId,
  required int streamPosition,
  required String senderId,
  required String msgtype,
  required String body,
  Map<String, Object?>? info,
  String? transactionId,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: '!alpha:example.org',
    senderId: senderId,
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 16, 10, streamPosition),
    streamPosition: streamPosition,
    transactionId: transactionId,
    content: <String, Object?>{
      'msgtype': msgtype,
      'body': body,
      'info': ?info,
      ...extra,
    },
  );
}
