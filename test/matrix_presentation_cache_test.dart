import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

void main() {
  test('empty presentation state does not persist a resume cursor', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: const <MatrixRoomSummary>[],
        syncCursor: 'stale-cursor',
      ),
    );

    expect(cache.lastSyncCursor, 'stale-cursor');
    expect(cache.hasReceivedSyncBatch.value, isFalse);

    cache.applySync(
      const MatrixSyncBatch(cursor: 'fresh-cursor', rooms: <MatrixRoomDelta>[]),
    );

    expect(cache.hasReceivedSyncBatch.value, isTrue);
    expect(cache.lastSyncCursor, 'fresh-cursor');
    expect(cache.snapshot().syncCursor, isNull);
  });

  test(
    'typing state stays ephemeral and clears only on an explicit update',
    () {
      final cache = MatrixPresentationCache();
      const roomId = '!typing:kite.test';

      cache.applySync(
        const MatrixSyncBatch(
          cursor: 'typing-1',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(roomId: roomId, typingUsers: <String>['Alice']),
          ],
        ),
      );
      expect(cache.typingUsersSignal(roomId).value, <String>['Alice']);

      cache.applySync(
        const MatrixSyncBatch(
          cursor: 'typing-2',
          rooms: <MatrixRoomDelta>[MatrixRoomDelta(roomId: roomId)],
        ),
      );
      expect(cache.typingUsersSignal(roomId).value, <String>['Alice']);

      final restored = MatrixPresentationCache(
        initialSnapshot: cache.snapshot(),
      );
      expect(restored.typingUsersSignal(roomId).value, isEmpty);

      cache.applySync(
        const MatrixSyncBatch(
          cursor: 'typing-3',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(roomId: roomId, typingUsers: <String>[]),
          ],
        ),
      );
      expect(cache.typingUsersSignal(roomId).value, isEmpty);
    },
  );

  test(
    'encryption recovery invalidation clears stale history but preserves rooms',
    () {
      final cachedEvent = _event(
        eventId: r'$encrypted',
        roomId: '!alpha:kite.test',
        position: 4,
        second: 4,
      );
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          syncCursor: 'stale-cursor',
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
      cache.applySync(
        const MatrixSyncBatch(
          cursor: 'incremental-cursor',
          rooms: <MatrixRoomDelta>[],
        ),
      );

      expect(cache.hasReceivedSyncBatch.value, isTrue);
      expect(cache.timelineSignal('!alpha:kite.test').value, isNotEmpty);

      cache.invalidateEncryptedHistory();

      expect(cache.roomOrder.value, <String>['!alpha:kite.test']);
      expect(
        cache.roomSummarySignal('!alpha:kite.test').value?.displayName,
        'Alpha',
      );
      expect(
        cache.timelineSignal('!alpha:kite.test').value.single.eventId,
        cachedEvent.eventId,
      );
      expect(cache.lastSyncCursor, isNull);
      expect(cache.hasReceivedSyncBatch.value, isFalse);
    },
  );

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
    'favourite updates stay leaf-level and preserve cached room metadata',
    () {
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          syncCursor: 'sync-1',
          rooms: <MatrixRoomSummary>[
            _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 4,
              second: 4,
              lastEventId: r'$cached',
              avatarUrl: 'mxc://kite.test/alpha',
              hasActiveCall: true,
              isMuted: true,
            ),
          ],
        ),
      );
      final orderBefore = cache.roomOrder.value;
      final before = cache.roomSummarySignal('!alpha:kite.test').value!;

      expect(cache.updateRoomFavourite('!alpha:kite.test', true), isTrue);

      final after = cache.roomSummarySignal('!alpha:kite.test').value!;
      expect(after.isFavourite, isTrue);
      expect(after.roomId, before.roomId);
      expect(after.displayName, before.displayName);
      expect(after.lastActivity, before.lastActivity);
      expect(after.streamPosition, before.streamPosition);
      expect(after.lastEventId, before.lastEventId);
      expect(after.avatarUrl, 'mxc://kite.test/alpha');
      expect(after.hasActiveCall, isTrue);
      expect(after.isMuted, isTrue);
      expect(cache.lastSyncCursor, 'sync-1');
      expect(identical(cache.roomOrder.value, orderBefore), isTrue);
      expect(cache.updateRoomFavourite('!alpha:kite.test', true), isFalse);
    },
  );

  test('read updates clear unread leaves without changing room order', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        syncCursor: 'sync-1',
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
            position: 4,
            second: 4,
            lastEventId: r'$cached',
            avatarUrl: 'mxc://kite.test/alpha',
            unreadCount: 3,
            highlightCount: 2,
            hasActiveCall: true,
            isMuted: true,
          ),
        ],
      ),
    );
    final orderBefore = cache.roomOrder.value;

    expect(cache.updateRoomRead('!alpha:kite.test'), isTrue);

    final after = cache.roomSummarySignal('!alpha:kite.test').value!;
    expect(after.unreadCount, 0);
    expect(after.highlightCount, 0);
    expect(after.lastEventId, r'$cached');
    expect(after.avatarUrl, 'mxc://kite.test/alpha');
    expect(after.hasActiveCall, isTrue);
    expect(after.isMuted, isTrue);
    expect(cache.lastSyncCursor, 'sync-1');
    expect(identical(cache.roomOrder.value, orderBefore), isTrue);
    expect(cache.updateRoomRead('!alpha:kite.test'), isFalse);
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

  test('sync applies avatar-only room metadata changes', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        syncCursor: 'sync-1',
        rooms: <MatrixRoomSummary>[
          _summary(
            roomId: '!alpha:kite.test',
            displayName: 'Alpha',
            position: 4,
            second: 4,
          ),
        ],
      ),
    );

    cache.applySync(
      MatrixSyncBatch(
        cursor: 'sync-2',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:kite.test',
            summary: _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 4,
              second: 4,
              avatarUrl: 'mxc://kite.test/alpha',
            ),
          ),
        ],
      ),
    );

    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.avatarUrl,
      'mxc://kite.test/alpha',
    );
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
    'redactions strip cached event content and survive snapshot restore',
    () {
      final cache = MatrixPresentationCache();
      final roomId = '!alpha:kite.test';
      cache.applySync(
        MatrixSyncBatch(
          cursor: 'before-redaction',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: roomId,
              summary: _summary(
                roomId: roomId,
                displayName: 'Alpha',
                position: 1,
                second: 1,
                lastEventId: r'$target',
              ),
              timelineEvents: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$target',
                  roomId: roomId,
                  senderId: '@alice:kite.test',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 14, 11, 20, 1),
                  streamPosition: 1,
                  content: const <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'delete me',
                  },
                ),
              ],
            ),
          ],
        ),
      );
      cache.applySync(
        MatrixSyncBatch(
          cursor: 'after-redaction',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: roomId,
              timelineEvents: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$redaction',
                  roomId: roomId,
                  senderId: '@alice:kite.test',
                  type: 'm.room.redaction',
                  originServerTimestamp: DateTime.utc(2026, 9, 14, 11, 20, 2),
                  streamPosition: 2,
                  redactsEventId: r'$target',
                ),
              ],
            ),
          ],
        ),
      );

      final target = cache
          .timelineSignal(roomId)
          .value
          .firstWhere((event) => event.eventId == r'$target');
      expect(target.redacted, isTrue);
      expect(target.content, isEmpty);

      final restored = MatrixPresentationCache(
        initialSnapshot: cache.snapshot(),
      );
      final restoredTarget = restored
          .timelineSignal(roomId)
          .value
          .firstWhere((event) => event.eventId == r'$target');
      expect(restoredTarget.redacted, isTrue);
      expect(restoredTarget.content, isEmpty);
    },
  );

  test(
    'sync removes left room presentation state without disturbing peers',
    () {
      final alphaEvent = _event(
        eventId: r'$alpha',
        roomId: '!alpha:kite.test',
        position: 4,
        second: 4,
      );
      final beta = _summary(
        roomId: '!beta:kite.test',
        displayName: 'Beta',
        position: 5,
        second: 5,
      );
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            _summary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha',
              position: 4,
              second: 4,
              lastEventId: alphaEvent.eventId,
            ),
            beta,
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!alpha:kite.test': <MatrixTimelineEvent>[alphaEvent],
          },
          syncCursor: 'before-left',
        ),
      );
      final betaBefore = cache.roomSummarySignal('!beta:kite.test').value;

      cache.applySync(
        const MatrixSyncBatch(
          cursor: 'after-left',
          rooms: <MatrixRoomDelta>[],
          removedRoomIds: <String>['!alpha:kite.test'],
        ),
      );

      expect(cache.lastSyncCursor, 'after-left');
      expect(cache.roomOrder.value, <String>['!beta:kite.test']);
      expect(cache.roomSummarySignal('!alpha:kite.test').value, isNull);
      expect(cache.timelineSignal('!alpha:kite.test').value, isEmpty);
      expect(
        identical(betaBefore, cache.roomSummarySignal('!beta:kite.test').value),
        isTrue,
      );
    },
  );

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

  test('duplicate removed room ids are rejected before cache mutation', () {
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
    final orderBefore = cache.roomOrder.value;

    expect(
      () => cache.applySync(
        const MatrixSyncBatch(
          cursor: 'rejected',
          rooms: <MatrixRoomDelta>[],
          removedRoomIds: <String>['!alpha:kite.test', '!alpha:kite.test'],
        ),
      ),
      throwsArgumentError,
    );

    expect(cache.lastSyncCursor, 'stable');
    expect(cache.roomSummarySignal('!alpha:kite.test').value, isNotNull);
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

  test(
    'bounded snapshots retain the latest message behind state-event noise',
    () {
      final cache = MatrixPresentationCache();
      cache.applySync(
        MatrixSyncBatch(
          cursor: 'stable',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:kite.test',
              summary: _summary(
                roomId: '!alpha:kite.test',
                displayName: 'Alpha',
                position: 5,
                second: 5,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                _event(
                  eventId: r'$message',
                  roomId: '!alpha:kite.test',
                  position: 1,
                  second: 1,
                ),
                for (var position = 2; position <= 5; position += 1)
                  _event(
                    eventId: '\$state-$position',
                    roomId: '!alpha:kite.test',
                    position: position,
                    second: position,
                    type: 'm.room.member',
                  ),
              ],
            ),
          ],
        ),
      );

      final snapshot = cache.snapshot(timelineEventLimitPerRoom: 3);
      final events = snapshot.timelines['!alpha:kite.test']!;

      expect(events, hasLength(3));
      expect(events.first.eventId, r'$message');
      expect(events.skip(1).map((event) => event.eventId), <String>[
        r'$state-4',
        r'$state-5',
      ]);
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
              hasActiveCall: true,
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
    expect(
      cache.roomSummarySignal('!alpha:kite.test').value?.hasActiveCall,
      isTrue,
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
  test('read receipt updates merge by user and stay ephemeral', () {
    final cache = MatrixPresentationCache();
    const roomId = '!receipts:kite.test';

    cache.applySync(
      const MatrixSyncBatch(
        cursor: 'receipts-1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: roomId,
            readReceipts: <MatrixReadReceipt>[
              MatrixReadReceipt(
                eventId: r'$one',
                userId: '@alice:kite.test',
                displayName: 'Alice',
              ),
              MatrixReadReceipt(
                eventId: r'$one',
                userId: '@bob:kite.test',
                displayName: 'Bob',
              ),
            ],
          ),
        ],
      ),
    );
    expect(cache.readReceiptsSignal(roomId).value.length, 2);

    cache.applySync(
      const MatrixSyncBatch(
        cursor: 'receipts-2',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: roomId,
            readReceipts: <MatrixReadReceipt>[
              MatrixReadReceipt(
                eventId: r'$two',
                userId: '@alice:kite.test',
                displayName: 'Alice',
              ),
            ],
          ),
        ],
      ),
    );
    final receipts = cache.readReceiptsSignal(roomId).value;
    expect(
      receipts.map((receipt) => '${receipt.userId}|${receipt.eventId}'),
      <String>[r'@alice:kite.test|$two', r'@bob:kite.test|$one'],
    );

    cache.restore(
      MatrixPresentationSnapshot(rooms: const <MatrixRoomSummary>[]),
    );
    expect(cache.readReceiptsSignal(roomId).value, isEmpty);
  });
}

MatrixRoomSummary _summary({
  required String roomId,
  required String displayName,
  required int position,
  required int second,
  String? lastEventId,
  String? avatarUrl,
  int unreadCount = 0,
  int highlightCount = 0,
  bool hasActiveCall = false,
  bool isMuted = false,
}) {
  return MatrixRoomSummary(
    roomId: roomId,
    displayName: displayName,
    lastActivity: DateTime.utc(2026, 9, 14, 11, 20, second),
    streamPosition: position,
    lastEventId: lastEventId,
    avatarUrl: avatarUrl,
    unreadCount: unreadCount,
    highlightCount: highlightCount,
    hasActiveCall: hasActiveCall,
    isMuted: isMuted,
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
