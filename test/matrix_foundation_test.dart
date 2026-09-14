import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_foundation.dart';

void main() {
  group('MatrixEventReducer', () {
    test('deduplicates and deterministically orders sync events', () {
      final existing = <MatrixEventEnvelope>[
        event('e1', order: 1, summary: 'one'),
        event('e3', order: 3, summary: 'stale'),
      ];
      final incoming = <MatrixEventEnvelope>[
        event('e2', order: 2, summary: 'two'),
        event('e3', order: 3, summary: 'fresh'),
      ];

      final merged = MatrixEventReducer.merge(existing, incoming);

      expect(merged.map((item) => item.eventId), <String>['e1', 'e2', 'e3']);
      expect(merged.last.summary, 'fresh');
    });

    test('replaces local echo with remote event sharing transaction id', () {
      final localEcho = event(
        'local-t1',
        order: 10,
        transactionId: 't1',
        summary: 'pending',
      );
      final remote = event(
        r'$remote',
        order: 11,
        transactionId: 't1',
        summary: 'sent',
      );

      final merged = MatrixEventReducer.merge(
        <MatrixEventEnvelope>[localEcho],
        <MatrixEventEnvelope>[remote],
      );

      expect(merged, hasLength(1));
      expect(merged.single.eventId, r'$remote');
    });
  });

  group('MatrixPresentationCache', () {
    test('renders seeded room and timeline synchronously', () {
      final cachedEvent = event('cached', order: 4, summary: 'cached body');
      final cache = MatrixPresentationCache(
        PresentationSnapshot(
          rooms: const <RoomPresentation>[
            RoomPresentation(roomId: '!room:test', name: 'Cached room'),
          ],
          timelines: <String, List<MatrixEventEnvelope>>{
            '!room:test': <MatrixEventEnvelope>[cachedEvent],
          },
        ),
      );

      expect(cache.rooms.single.name, 'Cached room');
      expect(cache.timeline('!room:test').single.summary, 'cached body');
    });

    test(
      'incremental sync preserves known screens and updates only target room',
      () {
        final cache = MatrixPresentationCache(
          PresentationSnapshot(
            rooms: const <RoomPresentation>[
              RoomPresentation(roomId: '!one:test', name: 'One'),
              RoomPresentation(roomId: '!two:test', name: 'Two'),
            ],
            timelines: <String, List<MatrixEventEnvelope>>{
              '!one:test': <MatrixEventEnvelope>[
                event('one-old', roomId: '!one:test', order: 1),
              ],
              '!two:test': <MatrixEventEnvelope>[
                event('two-old', roomId: '!two:test', order: 1),
              ],
            },
          ),
        );

        cache.applyEvents('!one:test', <MatrixEventEnvelope>[
          event('one-new', roomId: '!one:test', order: 2),
        ]);

        expect(
          cache.rooms.map((room) => room.roomId),
          containsAll(<String>['!one:test', '!two:test']),
        );
        expect(
          cache.timeline('!one:test').map((item) => item.eventId),
          <String>['one-old', 'one-new'],
        );
        expect(cache.timeline('!two:test').single.eventId, 'two-old');
        expect(cache.room('!one:test')?.latestEventId, 'one-new');
      },
    );

    test('snapshot preserves back-pagination continuation tokens', () {
      final cache = MatrixPresentationCache(
        const PresentationSnapshot(
          backPaginationTokens: <String, String?>{'!room:test': 'older-2'},
        ),
      );

      final snapshot = cache.snapshot();

      expect(snapshot.backPaginationTokens['!room:test'], 'older-2');
      expect(cache.hasBackPaginationToken('!room:test'), isTrue);
    });
  });

  group('TimelineBackPaginationController', () {
    test(
      'automatically loads and merges older events near the leading edge',
      () async {
        final cache = MatrixPresentationCache(
          PresentationSnapshot(
            timelines: <String, List<MatrixEventEnvelope>>{
              '!room:test': <MatrixEventEnvelope>[event('newer', order: 20)],
            },
            backPaginationTokens: const <String, String?>{
              '!room:test': 'older-1',
            },
          ),
        );
        final requestedTokens = <String>[];
        final controller = TimelineBackPaginationController(
          cache: cache,
          prefetchThreshold: 5,
          loadPage: (roomId, token) async {
            requestedTokens.add(token);
            return BackPaginationPage(
              events: <MatrixEventEnvelope>[
                event('older', order: 10),
                event('newer', order: 20, summary: 'deduped newer'),
              ],
              previousToken: 'older-2',
            );
          },
        );

        expect(
          await controller.onViewport(
            roomId: '!room:test',
            firstVisibleIndex: 4,
          ),
          isTrue,
        );

        expect(requestedTokens, <String>['older-1']);
        expect(
          cache.timeline('!room:test').map((item) => item.eventId),
          <String>['older', 'newer'],
        );
        expect(cache.timeline('!room:test').last.summary, 'deduped newer');
        expect(cache.backPaginationToken('!room:test'), 'older-2');
      },
    );

    test(
      'does not fetch away from edge or after pagination is exhausted',
      () async {
        final cache = MatrixPresentationCache(
          const PresentationSnapshot(
            backPaginationTokens: <String, String?>{'!room:test': 'older-1'},
          ),
        );
        var calls = 0;
        final controller = TimelineBackPaginationController(
          cache: cache,
          prefetchThreshold: 5,
          loadPage: (roomId, token) async {
            calls += 1;
            return const BackPaginationPage(
              events: <MatrixEventEnvelope>[],
              previousToken: null,
            );
          },
        );

        expect(
          await controller.onViewport(
            roomId: '!room:test',
            firstVisibleIndex: 6,
          ),
          isFalse,
        );
        expect(calls, 0);

        expect(
          await controller.onViewport(
            roomId: '!room:test',
            firstVisibleIndex: 5,
          ),
          isTrue,
        );
        expect(calls, 1);
        expect(cache.hasBackPaginationToken('!room:test'), isTrue);
        expect(cache.backPaginationToken('!room:test'), isNull);

        expect(
          await controller.onViewport(
            roomId: '!room:test',
            firstVisibleIndex: 0,
          ),
          isFalse,
        );
        expect(calls, 1);
      },
    );

    test('coalesces overlapping viewport triggers to one request', () async {
      final cache = MatrixPresentationCache(
        const PresentationSnapshot(
          backPaginationTokens: <String, String?>{'!room:test': 'older-1'},
        ),
      );
      final completer = Completer<BackPaginationPage>();
      var calls = 0;
      final controller = TimelineBackPaginationController(
        cache: cache,
        loadPage: (roomId, token) {
          calls += 1;
          return completer.future;
        },
      );

      final first = controller.onViewport(
        roomId: '!room:test',
        firstVisibleIndex: 0,
      );
      final second = controller.onViewport(
        roomId: '!room:test',
        firstVisibleIndex: 0,
      );

      expect(controller.isLoading('!room:test'), isTrue);
      expect(await second, isFalse);
      expect(calls, 1);

      completer.complete(
        const BackPaginationPage(
          events: <MatrixEventEnvelope>[],
          previousToken: null,
        ),
      );
      expect(await first, isTrue);
      expect(controller.isLoading('!room:test'), isFalse);
    });
  });

  group('OfflineSendQueue', () {
    test(
      'holds sends offline then exposes deterministic retry states',
      () async {
        final queue = OfflineSendQueue()..setOnline(false);
        queue.enqueue(transactionId: 't1', roomId: '!room:test', body: 'hello');
        var calls = 0;

        await queue.drain((send) async {
          calls += 1;
          return const SendAttemptResult.retryableFailure();
        });

        expect(calls, 0);
        expect(queue.sends.single.state, OfflineSendState.queued);
        expect(queue.sends.single.attempts, 0);

        queue.setOnline(true);
        await queue.drain((send) async {
          calls += 1;
          return const SendAttemptResult.retryableFailure();
        });

        expect(calls, 1);
        expect(queue.sends.single.state, OfflineSendState.retryWaiting);
        expect(queue.sends.single.attempts, 1);

        queue.retryNow('t1');
        expect(queue.sends.single.state, OfflineSendState.queued);

        await queue.drain((send) async {
          calls += 1;
          return const SendAttemptResult.sent(r'$event');
        });

        expect(calls, 2);
        expect(queue.sends.single.state, OfflineSendState.sent);
        expect(queue.sends.single.attempts, 2);
        expect(queue.sends.single.eventId, r'$event');
      },
    );

    test('enqueue is idempotent by transaction id', () {
      final queue = OfflineSendQueue();

      final first = queue.enqueue(
        transactionId: 't1',
        roomId: '!room:test',
        body: 'first',
      );
      final second = queue.enqueue(
        transactionId: 't1',
        roomId: '!room:test',
        body: 'second',
      );

      expect(identical(first, second), isTrue);
      expect(queue.sends, hasLength(1));
      expect(queue.sends.single.body, 'first');
    });
  });
}

MatrixEventEnvelope event(
  String eventId, {
  String roomId = '!room:test',
  required int order,
  String summary = 'body',
  String? transactionId,
}) {
  return MatrixEventEnvelope(
    eventId: eventId,
    roomId: roomId,
    syncOrder: order,
    timestamp: DateTime.utc(2026, 1, 1, 12, 0, order),
    senderId: '@alice:test',
    summary: summary,
    transactionId: transactionId,
  );
}
