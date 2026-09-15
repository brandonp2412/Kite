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

  test(
    'restoring a snapshot clears stale leaves without rewriting equal state',
    () {
      final alpha = _summary(
        roomId: '!alpha:kite.test',
        displayName: 'Alpha stale',
        position: 4,
        second: 4,
      );
      final beta = _summary(
        roomId: '!beta:kite.test',
        displayName: 'Beta stable',
        position: 5,
        second: 5,
      );
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[alpha, beta],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!alpha:kite.test': <MatrixTimelineEvent>[
              _event(
                eventId: r'$alpha-stale',
                roomId: '!alpha:kite.test',
                position: 4,
                second: 4,
              ),
            ],
            '!beta:kite.test': <MatrixTimelineEvent>[
              _event(
                eventId: r'$beta-stale',
                roomId: '!beta:kite.test',
                position: 5,
                second: 5,
              ),
            ],
          },
          syncCursor: 'before-restore',
        ),
      );
      final betaBefore = cache.roomSummarySignal('!beta:kite.test').value;

      cache.restore(
        MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            _summary(
              roomId: '!beta:kite.test',
              displayName: 'Beta stable',
              position: 5,
              second: 5,
            ),
          ],
          syncCursor: 'restored',
        ),
      );

      expect(cache.lastSyncCursor, 'restored');
      expect(cache.roomOrder.value, <String>['!beta:kite.test']);
      expect(cache.roomSummarySignal('!alpha:kite.test').value, isNull);
      expect(cache.timelineSignal('!alpha:kite.test').value, isEmpty);
      expect(cache.timelineSignal('!beta:kite.test').value, isEmpty);
      expect(
        identical(betaBefore, cache.roomSummarySignal('!beta:kite.test').value),
        isTrue,
      );
    },
  );

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
    'persisted snapshots bound rooms and retain only recent timeline events',
    () {
      final cache = MatrixPresentationCache();
      for (final entry in <(String, int)>[
        ('!alpha:kite.test', 3),
        ('!beta:kite.test', 2),
        ('!gamma:kite.test', 1),
      ]) {
        final roomId = entry.$1;
        final position = entry.$2;
        cache.applySync(
          MatrixSyncBatch(
            cursor: 'cursor-$position',
            rooms: <MatrixRoomDelta>[
              MatrixRoomDelta(
                roomId: roomId,
                summary: _summary(
                  roomId: roomId,
                  displayName: roomId,
                  position: position,
                  second: position,
                ),
                timelineEvents: <MatrixTimelineEvent>[
                  _event(
                    eventId: '\$$position-1',
                    roomId: roomId,
                    position: position * 10 + 1,
                    second: 1,
                  ),
                  _event(
                    eventId: '\$$position-2',
                    roomId: roomId,
                    position: position * 10 + 2,
                    second: 2,
                  ),
                  _event(
                    eventId: '\$$position-3',
                    roomId: roomId,
                    position: position * 10 + 3,
                    second: 3,
                  ),
                ],
              ),
            ],
          ),
        );
      }

      final snapshot = cache.snapshot(
        roomLimit: 2,
        timelineEventLimitPerRoom: 2,
      );

      expect(snapshot.rooms.map((room) => room.roomId), <String>[
        '!alpha:kite.test',
        '!beta:kite.test',
      ]);
      expect(snapshot.timelines.keys, <String>{
        '!alpha:kite.test',
        '!beta:kite.test',
      });
      expect(
        snapshot.timelines['!alpha:kite.test']!.map((event) => event.eventId),
        <String>[r'$3-2', r'$3-3'],
      );
      expect(snapshot.timelines.containsKey('!gamma:kite.test'), isFalse);
      expect(snapshot.syncCursor, 'cursor-1');
      expect(cache.roomOrder.value, hasLength(3));
      expect(cache.timelineSignal('!alpha:kite.test').value, hasLength(3));
    },
  );

  test('equivalent JSON content does not rewrite a timeline signal', () {
    final cache = MatrixPresentationCache();
    final first = MatrixTimelineEvent(
      eventId: r'$same',
      roomId: '!alpha:kite.test',
      senderId: '@alice:kite.test',
      type: 'm.room.message',
      originServerTimestamp: DateTime.utc(2026, 9, 14, 11, 20, 6),
      streamPosition: 6,
      content: <String, Object?>{
        'body': 'stable',
        'metadata': <String, Object?>{'a': 1, 'b': 2},
      },
    );
    cache.applySync(
      MatrixSyncBatch(
        cursor: 'first',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            timelineEvents: <MatrixTimelineEvent>[first],
          ),
        ],
      ),
    );
    final timelineBefore = cache.timelineSignal('!alpha:kite.test').value;

    final equivalent = MatrixTimelineEvent(
      eventId: r'$same',
      roomId: '!alpha:kite.test',
      senderId: '@alice:kite.test',
      type: 'm.room.message',
      originServerTimestamp: DateTime.utc(2026, 9, 14, 11, 20, 6),
      streamPosition: 6,
      content: <String, Object?>{
        'metadata': <String, Object?>{'b': 2, 'a': 1},
        'body': 'stable',
      },
    );
    cache.applySync(
      MatrixSyncBatch(
        cursor: 'second',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            timelineEvents: <MatrixTimelineEvent>[equivalent],
          ),
        ],
      ),
    );

    expect(
      identical(timelineBefore, cache.timelineSignal('!alpha:kite.test').value),
      isTrue,
    );
    expect(cache.lastSyncCursor, 'second');
  });

  test('leaf summary changes preserve room-order identity', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
            position: 9,
            second: 9,
            lastEventId: r'$alpha-1',
          ),
          _summary(
            roomId: '!beta:kite.test',
            displayName: 'Beta',
            position: 8,
            second: 8,
          ),
        ],
      ),
    );
    final orderBefore = cache.roomOrder.value;

    cache.applySync(
      MatrixSyncBatch(
        cursor: 'metadata-only',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            summary: _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alice renamed this room',
              position: 9,
              second: 9,
              lastEventId: r'$alpha-2',
            ),
          ),
        ],
      ),
    );

    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
      'Alice renamed this room',
    );
    expect(identical(orderBefore, cache.roomOrder.value), isTrue);
    expect(cache.lastSyncCursor, 'metadata-only');
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
