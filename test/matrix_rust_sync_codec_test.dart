import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  test('decodes native sync into deterministic presentation batches', () {
    final codec = MatrixRustSyncCodec();

    final decoded = codec.decodeSync(r'''
      {
        "cursor": "s42",
        "rooms": [
          {
            "roomId": "!alpha:kite.test",
            "displayName": "Alpha",
            "unreadCount": 3,
            "latestEventTimestamp": 2000,
            "prevBatch": "back-alpha",
            "events": [
              {
                "event_id": "$event1",
                "sender": "@alice:kite.test",
                "type": "m.room.message",
                "origin_server_ts": 1000,
                "content": {"msgtype": "m.text", "body": "one"}
              },
              {
                "event_id": "$event2",
                "sender": "@bob:kite.test",
                "type": "m.room.message",
                "origin_server_ts": 2000,
                "content": {"msgtype": "m.text", "body": "two"}
              }
            ]
          },
          {
            "roomId": "!empty:kite.test",
            "displayName": "Empty",
            "unreadCount": 0,
            "latestEventTimestamp": 500,
            "prevBatch": null,
            "events": []
          }
        ]
      }
    ''');

    expect(decoded.batch.cursor, 's42');
    expect(decoded.batch.rooms, hasLength(2));

    final alpha = decoded.batch.rooms.first;
    expect(alpha.summary!.displayName, 'Alpha');
    expect(alpha.summary!.unreadCount, 3);
    expect(alpha.summary!.lastEventId, r'$event2');
    expect(alpha.summary!.lastActivity.millisecondsSinceEpoch, 2000);
    expect(alpha.summary!.streamPosition, 2000);
    expect(alpha.timelineEvents.map((event) => event.streamPosition), <int>[
      1000,
      2000,
    ]);
    expect(alpha.timelineEvents.last.content['body'], 'two');

    final empty = decoded.batch.rooms.last;
    expect(empty.summary!.streamPosition, 500);
    expect(empty.summary!.lastActivity.millisecondsSinceEpoch, 500);
  });

  test('pagination continues the same monotonic event positions', () {
    final codec = MatrixRustSyncCodec();
    final sync = codec.decodeSync(r'''
      {
        "cursor": "s1",
        "rooms": [
          {
            "roomId": "!room:kite.test",
            "displayName": "Room",
            "unreadCount": 0,
            "latestEventTimestamp": 2000,
            "prevBatch": "back-1",
            "events": [
              {
                "event_id": "$new",
                "sender": "@alice:kite.test",
                "type": "m.room.message",
                "origin_server_ts": 2000,
                "content": {"body": "new"}
              }
            ]
          }
        ]
      }
    ''');

    final page = codec.decodePagination(r'''
      {
        "roomId": "!room:kite.test",
        "reachedStart": false,
        "events": [
          {
            "event_id": "$older-near",
            "sender": "@alice:kite.test",
            "type": "m.room.message",
            "origin_server_ts": 1500,
            "content": {"body": "near"}
          },
          {
            "event_id": "$older-far",
            "sender": "@alice:kite.test",
            "type": "m.room.message",
            "origin_server_ts": 1000,
            "content": {"body": "far"}
          }
        ]
      }
    ''');

    expect(page.roomId, '!room:kite.test');
    expect(page.reachedStart, isFalse);
    expect(page.events.map((event) => event.eventId), <String>[
      r'$older-far',
      r'$older-near',
    ]);
    expect(page.events.map((event) => event.streamPosition), <int>[1000, 1500]);

    final cache = MatrixPresentationCache();
    cache.applySync(sync.batch);
    cache.applySync(
      MatrixSyncBatch(
        cursor: sync.batch.cursor,
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(roomId: page.roomId, timelineEvents: page.events),
        ],
      ),
    );
    expect(
      cache
          .timelineSignal('!room:kite.test')
          .value
          .map((event) => event.eventId),
      <String>[r'$older-far', r'$older-near', r'$new'],
    );
  });

  test(
    'server timestamps keep post-restart updates newer than restored cache',
    () {
      final restored = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!room:kite.test',
              displayName: 'Before restart',
              lastActivity: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              streamPosition: 2000,
              unreadCount: 1,
            ),
          ],
        ),
      );
      final freshProcessCodec = MatrixRustSyncCodec();
      final sync = freshProcessCodec.decodeSync(r'''
      {
        "cursor": "after-restart",
        "rooms": [
          {
            "roomId": "!room:kite.test",
            "displayName": "After restart",
            "unreadCount": 2,
            "latestEventTimestamp": 3000,
            "prevBatch": null,
            "events": [
              {
                "event_id": "$afterRestart",
                "sender": "@alice:kite.test",
                "type": "m.room.message",
                "origin_server_ts": 3000,
                "content": {"body": "fresh"}
              }
            ]
          }
        ]
      }
    ''');

      restored.applySync(sync.batch);

      final summary = restored.roomSummarySignal('!room:kite.test').value!;
      expect(summary.displayName, 'After restart');
      expect(summary.unreadCount, 2);
      expect(summary.streamPosition, 3000);
      expect(
        restored.timelineSignal('!room:kite.test').value.single.eventId,
        r'$afterRestart',
      );

      final metadataOnly = freshProcessCodec.decodeSync(r'''
        {
          "cursor": "metadata-only",
          "rooms": [
            {
              "roomId": "!room:kite.test",
              "displayName": "After restart",
              "unreadCount": 4,
              "latestEventTimestamp": 3000,
              "latestEventId": "$afterRestart",
              "prevBatch": null,
              "events": []
            }
          ]
        }
      ''');
      restored.applySync(metadataOnly.batch);

      final metadataSummary = restored
          .roomSummarySignal('!room:kite.test')
          .value!;
      expect(metadataSummary.unreadCount, 4);
      expect(metadataSummary.lastEventId, r'$afterRestart');
    },
  );

  test(
    'rejects malformed native events before they reach presentation state',
    () {
      final codec = MatrixRustSyncCodec();

      expect(
        () => codec.decodeSync(r'''
        {
          "cursor": "s1",
          "rooms": [
            {
              "roomId": "!room:kite.test",
              "events": [
                {
                  "sender": "@alice:kite.test",
                  "type": "m.room.message",
                  "origin_server_ts": 1000,
                  "content": {}
                }
              ]
            }
          ]
        }
      '''),
        throwsFormatException,
      );
    },
  );
}
