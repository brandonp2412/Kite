import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

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

  test('malformed sync room data is rejected before any cache mutation', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
            position: 5,
            second: 5,
          ),
        ],
        syncCursor: 'stable',
      ),
    );
    final alphaBefore = cache.roomSummarySignal('!alpha:kite.test').value;
    final orderBefore = cache.roomOrder.value;

    expect(
      () => cache.applySync(
        MatrixSyncBatch(
          cursor: 'rejected',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!beta:kite.test',
              summary: _summary(
                roomId: '!beta:kite.test',
                displayName: 'Beta',
                position: 6,
                second: 6,
              ),
            ),
            MatrixRoomDelta(
              roomId: '!gamma:kite.test',
              summary: _summary(
                roomId: '!other:kite.test',
                displayName: 'Wrong owner',
                position: 7,
                second: 7,
              ),
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );

    expect(cache.lastSyncCursor, 'stable');
    expect(cache.roomSummarySignal('!beta:kite.test').value, isNull);
    expect(cache.roomSummarySignal('!gamma:kite.test').value, isNull);
    expect(
      identical(alphaBefore, cache.roomSummarySignal('!alpha:kite.test').value),
      isTrue,
    );
    expect(identical(orderBefore, cache.roomOrder.value), isTrue);
  });

  test('cross-room timeline events cannot contaminate sync or pagination', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 'stable',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$alpha-stable',
                roomId: '!alpha:kite.test',
                position: 1,
                second: 1,
              ),
            ],
          ),
        ],
      ),
    );
    final timelineBefore = cache.timelineSignal('!alpha:kite.test').value;

    expect(
      () => cache.applySync(
        MatrixSyncBatch(
          cursor: 'bad-sync',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:kite.test',
              timelineEvents: <MatrixTimelineEvent>[
                _event(
                  eventId: r'$wrong-sync-room',
                  roomId: '!beta:kite.test',
                  position: 2,
                  second: 2,
                ),
              ],
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => cache.applyPagination(
        MatrixPaginationPage(
          roomId: '!alpha:kite.test',
          events: <MatrixTimelineEvent>[
            _event(
              eventId: r'$wrong-page-room',
              roomId: '!beta:kite.test',
              position: 0,
              second: 0,
            ),
          ],
          reachedStart: false,
        ),
      ),
      throwsArgumentError,
    );

    expect(cache.lastSyncCursor, 'stable');
    expect(
      identical(timelineBefore, cache.timelineSignal('!alpha:kite.test').value),
      isTrue,
    );
    expect(
      cache
          .timelineSignal('!alpha:kite.test')
          .value
          .map((event) => event.eventId),
      <String>[r'$alpha-stable'],
    );
    expect(cache.timelineSignal('!beta:kite.test').value, isEmpty);
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
      expect(snapshot.syncCursor, isNull);
      expect(cache.roomOrder.value, hasLength(3));
      expect(cache.timelineSignal('!alpha:kite.test').value, hasLength(3));
    },
  );

  test('bounded snapshots retain the cursor when no rooms are omitted', () {
    final cache = MatrixPresentationCache();
    for (final entry in <(String, int)>[
      ('!alpha:kite.test', 2),
      ('!beta:kite.test', 1),
    ]) {
      cache.applySync(
        MatrixSyncBatch(
          cursor: 'cursor-${entry.$2}',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: entry.$1,
              summary: _summary(
                roomId: entry.$1,
                displayName: entry.$1,
                position: entry.$2,
                second: entry.$2,
              ),
            ),
          ],
        ),
      );
    }

    final snapshot = cache.snapshot(roomLimit: 2);

    expect(snapshot.rooms, hasLength(2));
    expect(snapshot.syncCursor, 'cursor-1');
  });

  test('timeline event content is deeply isolated from mutable inputs', () {
    final metadata = <String, Object?>{'count': 1};
    final tags = <Object?>['stable'];
    final source = <String, Object?>{
      'body': 'before',
      'metadata': metadata,
      'tags': tags,
    };
    final event = MatrixTimelineEvent(
      eventId: r'$isolated',
      roomId: '!alpha:kite.test',
      senderId: '@alice:kite.test',
      type: 'm.room.message',
      originServerTimestamp: DateTime.utc(2026, 9, 15),
      streamPosition: 1,
      content: source,
    );

    source['body'] = 'after';
    metadata['count'] = 2;
    tags.add('mutated');

    expect(event.content['body'], 'before');
    expect(event.content['metadata'], <String, Object?>{'count': 1});
    expect(event.content['tags'], <Object?>['stable']);
    expect(
      () => (event.content['metadata']! as Map<String, Object?>)['count'] = 3,
      throwsUnsupportedError,
    );
    expect(
      () => (event.content['tags']! as List<Object?>).add('blocked'),
      throwsUnsupportedError,
    );
  });

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

  test(
    'malformed restored snapshots are rejected before replacing cached state',
    () {
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 5,
              second: 5,
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!alpha:kite.test': <MatrixTimelineEvent>[
              _event(
                eventId: r'$alpha-stable',
                roomId: '!alpha:kite.test',
                position: 5,
                second: 5,
              ),
            ],
          },
          syncCursor: 'stable',
        ),
      );
      final alphaBefore = cache.roomSummarySignal('!alpha:kite.test').value;
      final timelineBefore = cache.timelineSignal('!alpha:kite.test').value;
      final orderBefore = cache.roomOrder.value;

      expect(
        () => cache.restore(
          MatrixPresentationSnapshot(
            rooms: <MatrixRoomSummary>[
              _summary(
                roomId: '!beta:kite.test',
                displayName: 'Beta',
                position: 6,
                second: 6,
              ),
            ],
            timelines: <String, List<MatrixTimelineEvent>>{
              '!beta:kite.test': <MatrixTimelineEvent>[
                _event(
                  eventId: r'$wrong-restored-room',
                  roomId: '!gamma:kite.test',
                  position: 6,
                  second: 6,
                ),
              ],
            },
            syncCursor: 'rejected',
          ),
        ),
        throwsArgumentError,
      );

      expect(cache.lastSyncCursor, 'stable');
      expect(cache.roomSummarySignal('!beta:kite.test').value, isNull);
      expect(
        identical(
          alphaBefore,
          cache.roomSummarySignal('!alpha:kite.test').value,
        ),
        isTrue,
      );
      expect(
        identical(
          timelineBefore,
          cache.timelineSignal('!alpha:kite.test').value,
        ),
        isTrue,
      );
      expect(identical(orderBefore, cache.roomOrder.value), isTrue);
    },
  );

  test('restoration publishes cached presentation signals atomically', () {
    final cache = MatrixPresentationCache();
    final alpha = cache.roomSummarySignal('!alpha:kite.test');
    final beta = cache.roomSummarySignal('!beta:kite.test');
    var effectRuns = 0;
    final dispose = effect(() {
      effectRuns += 1;
      alpha.value;
      beta.value;
      cache.roomOrder.value;
    });
    addTearDown(dispose);

    expect(effectRuns, 1);

    cache.restore(
      MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
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
        syncCursor: 'cached',
      ),
    );

    expect(effectRuns, 2);
    expect(cache.lastSyncCursor, 'cached');
    expect(cache.roomOrder.value, <String>[
      '!alpha:kite.test',
      '!beta:kite.test',
    ]);
  });

  test(
    'partial sync presentation chunks do not advance the persisted cursor',
    () {
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: const <MatrixRoomSummary>[],
          syncCursor: 'previous',
        ),
      );

      cache.applySync(
        MatrixSyncBatch(
          cursor: 'next',
          commitCursor: false,
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:kite.test',
              summary: _summary(
                roomId: '!alpha:kite.test',
                displayName: 'Alpha',
                position: 9,
                second: 9,
              ),
            ),
          ],
        ),
      );

      expect(cache.lastSyncCursor, 'previous');
      expect(cache.roomOrder.value, <String>['!alpha:kite.test']);

      cache.applySync(
        const MatrixSyncBatch(cursor: 'next', rooms: <MatrixRoomDelta>[]),
      );
      expect(cache.lastSyncCursor, 'next');
    },
  );

  test('sync publishes related presentation signal changes atomically', () {
    final cache = MatrixPresentationCache();
    final alpha = cache.roomSummarySignal('!alpha:kite.test');
    final beta = cache.roomSummarySignal('!beta:kite.test');
    var effectRuns = 0;
    final dispose = effect(() {
      effectRuns += 1;
      alpha.value;
      beta.value;
      cache.roomOrder.value;
    });
    addTearDown(dispose);

    expect(effectRuns, 1);

    cache.applySync(
      MatrixSyncBatch(
        cursor: 'initial',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            summary: _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 9,
              second: 9,
            ),
          ),
          MatrixRoomDelta(
            roomId: '!beta:kite.test',
            summary: _summary(
              roomId: '!beta:kite.test',
              displayName: 'Beta',
              position: 8,
              second: 8,
            ),
          ),
        ],
      ),
    );

    expect(effectRuns, 2);
    expect(cache.roomOrder.value, <String>[
      '!alpha:kite.test',
      '!beta:kite.test',
    ]);
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
              highlightCount: 1,
            ),
          ),
        ],
      ),
    );

    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
      'Alice renamed this room',
    );
    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.highlightCount,
      1,
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
  int highlightCount = 0,
}) {
  return MatrixRoomSummary(
    roomId: roomId,
    displayName: displayName,
    lastActivity: DateTime.utc(2026, 9, 14, 11, 20, second),
    streamPosition: position,
    lastEventId: lastEventId,
    highlightCount: highlightCount,
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
