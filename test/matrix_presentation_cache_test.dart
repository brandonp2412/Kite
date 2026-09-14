import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  test('restored presentation data is readable synchronously before sync', () {
    final cachedEvent = _event(
      eventId: r'$cached',
      roomId: '!alpha:kite.test',
      position: 4,
      second: 4,
    );
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
            position: 4,
            second: 4,
            lastEventId: cachedEvent.eventId,
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!alpha:kite.test': <MatrixTimelineEvent>[cachedEvent],
        },
      ),
    );

    expect(cache.roomOrder.value, <String>['!alpha:kite.test']);
    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
      'Alpha',
    );
    expect(
      cache.timelineSignal('!alpha:kite.test').value.single.eventId,
      r'$cached',
    );
    expect(cache.lastSyncCursor, isNull);
  });

  test('sync deduplicates and deterministically orders overlapping events', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            summary: _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 3,
              second: 3,
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$three',
                roomId: '!alpha:kite.test',
                position: 3,
                second: 3,
              ),
              _event(
                eventId: r'$one',
                roomId: '!alpha:kite.test',
                position: 1,
                second: 1,
              ),
            ],
          ),
        ],
      ),
    );

    cache.applySync(
      MatrixSyncBatch(
        cursor: 's2',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            summary: _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha renamed',
              position: 4,
              second: 4,
              lastEventId: r'$three',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$two',
                roomId: '!alpha:kite.test',
                position: 2,
                second: 2,
              ),
              _event(
                eventId: r'$three',
                roomId: '!alpha:kite.test',
                position: 4,
                second: 4,
                type: 'm.room.message.edited',
              ),
            ],
          ),
        ],
      ),
    );

    final events = cache.timelineSignal('!alpha:kite.test').value;
    expect(events.map((event) => event.eventId), <String>[
      r'$one',
      r'$two',
      r'$three',
    ]);
    expect(events.last.streamPosition, 4);
    expect(events.last.type, 'm.room.message.edited');
    expect(cache.lastSyncCursor, 's2');
    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
      'Alpha renamed',
    );
  });

  test(
    'stale batches cannot regress room state or rewrite unaffected signals',
    () {
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha current',
              position: 9,
              second: 9,
            ),
            _summary(
              roomId: '!beta:kite.test',
              displayName: 'Beta',
              position: 8,
              second: 8,
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!beta:kite.test': <MatrixTimelineEvent>[
              _event(
                eventId: r'$beta',
                roomId: '!beta:kite.test',
                position: 8,
                second: 8,
              ),
            ],
          },
        ),
      );
      final betaSummaryBefore = cache
          .roomSummarySignal('!beta:kite.test')
          .value;
      final betaTimelineBefore = cache.timelineSignal('!beta:kite.test').value;
      final roomOrderBefore = cache.roomOrder.value;

      cache.applySync(
        MatrixSyncBatch(
          cursor: 'stale-overlap',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:kite.test',
              summary: _summary(
                roomId: '!alpha:kite.test',
                displayName: 'Alpha stale',
                position: 2,
                second: 2,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                _event(
                  eventId: r'$alpha-new',
                  roomId: '!alpha:kite.test',
                  position: 10,
                  second: 10,
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
        'Alpha current',
      );
      expect(
        identical(
          betaSummaryBefore,
          cache.roomSummarySignal('!beta:kite.test').value,
        ),
        isTrue,
      );
      expect(
        identical(
          betaTimelineBefore,
          cache.timelineSignal('!beta:kite.test').value,
        ),
        isTrue,
      );
      expect(identical(roomOrderBefore, cache.roomOrder.value), isTrue);
    },
  );
}

MatrixRoomSummary _summary({
  required String roomId,
  required String displayName,
  required int position,
  required int second,
  String? lastEventId,
}) {
  return MatrixRoomSummary(
    roomId: roomId,
    displayName: displayName,
    lastActivity: DateTime.utc(2026, 9, 14, 11, 20, second),
    streamPosition: position,
    lastEventId: lastEventId,
  );
}

MatrixTimelineEvent _event({
  required String eventId,
  required String roomId,
  required int position,
  required int second,
  String type = 'm.room.message',
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: roomId,
    senderId: '@alice:kite.test',
    type: type,
    originServerTimestamp: DateTime.utc(2026, 9, 14, 11, 20, second),
    streamPosition: position,
    content: <String, Object?>{'body': eventId},
  );
}
