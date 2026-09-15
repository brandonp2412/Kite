import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:signals/signals.dart';

void main() {
  test(
    'pagination exposes leaf loading state and coalesces requests',
    () async {
      final engine = _PaginationFakeMatrixEngine();
      final pages = <MatrixPaginationPage>[];
      final controller = MatrixBackPaginationController(
        engine: engine,
        applyPage: pages.add,
        edgeThreshold: 4,
      );
      final state = controller.stateSignal('!room:kite.test');

      expect(state.value.phase, MatrixPaginationPhase.idle);

      final first = controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 4,
        hasMoreHistory: true,
      );
      final second = controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 1,
        hasMoreHistory: true,
      );

      expect(engine.paginationCalls, <String>['!room:kite.test']);
      expect(controller.isPaginating('!room:kite.test'), isTrue);
      expect(state.value.phase, MatrixPaginationPhase.loading);

      engine.completePagination();
      await Future.wait(<Future<void>>[first, second]);

      expect(controller.isPaginating('!room:kite.test'), isFalse);
      expect(state.value.phase, MatrixPaginationPhase.idle);
      expect(state.value.reachedStart, isFalse);
      expect(pages, hasLength(1));
      await engine.close();
    },
  );

  test(
    'pagination publishes timeline and loading completion atomically',
    () async {
      final engine = _PaginationFakeMatrixEngine();
      final appliedPages = signal(0);
      final controller = MatrixBackPaginationController(
        engine: engine,
        applyPage: (_) => appliedPages.value += 1,
      );
      final state = controller.stateSignal('!room:kite.test');
      var effectRuns = 0;
      final dispose = effect(() {
        effectRuns += 1;
        state.value;
        appliedPages.value;
      });
      addTearDown(dispose);

      expect(effectRuns, 1);
      final pagination = controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(effectRuns, 2);
      expect(state.value.phase, MatrixPaginationPhase.loading);

      engine.completePagination();
      await pagination;

      expect(appliedPages.value, 1);
      expect(state.value.phase, MatrixPaginationPhase.idle);
      expect(effectRuns, 3);
      await engine.close();
    },
  );

  test('pagination failure is observable, clearable, and retryable', () async {
    final engine = _PaginationFakeMatrixEngine();
    final controller = MatrixBackPaginationController(
      engine: engine,
      applyPage: (_) {},
    );
    final state = controller.stateSignal('!room:kite.test');

    final failed = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    final failure = StateError('deterministic pagination failure');
    engine.failPagination(failure);

    await expectLater(failed, throwsA(same(failure)));
    expect(controller.isPaginating('!room:kite.test'), isFalse);
    expect(state.value.phase, MatrixPaginationPhase.failed);
    expect(state.value.error, same(failure));

    controller.clearFailure('!room:kite.test');
    expect(state.value.phase, MatrixPaginationPhase.idle);

    final retry = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    expect(engine.paginationCalls, <String>[
      '!room:kite.test',
      '!room:kite.test',
    ]);
    expect(state.value.phase, MatrixPaginationPhase.loading);

    engine.completePagination();
    await retry;
    expect(state.value.phase, MatrixPaginationPhase.idle);
    await engine.close();
  });

  test('synchronous pagination failure still leaves retryable state', () async {
    final failure = StateError('synchronous pagination failure');
    final engine = _PaginationFakeMatrixEngine(syncFailure: failure);
    final controller = MatrixBackPaginationController(
      engine: engine,
      applyPage: (_) {},
    );
    final state = controller.stateSignal('!room:kite.test');

    await expectLater(
      controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: true,
      ),
      throwsA(same(failure)),
    );

    expect(controller.isPaginating('!room:kite.test'), isFalse);
    expect(state.value.phase, MatrixPaginationPhase.failed);
    expect(state.value.error, same(failure));

    controller.clearFailure('!room:kite.test');
    expect(state.value.phase, MatrixPaginationPhase.idle);
    await engine.close();
  });

  test(
    'pagination remains idle when history is exhausted or edge is distant',
    () async {
      final engine = _PaginationFakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
        applyPage: (_) {},
        edgeThreshold: 3,
      );
      final state = controller.stateSignal('!room:kite.test');

      await controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: false,
      );
      await controller.maybePaginate(
        roomId: '!room:kite.test',
        firstVisibleIndex: 4,
        hasMoreHistory: true,
      );

      expect(engine.paginationCalls, isEmpty);
      expect(state.value.phase, MatrixPaginationPhase.idle);
      await engine.close();
    },
  );

  test('lifecycle cancellation ignores stale pagination completion', () async {
    final engine = _PaginationFakeMatrixEngine();
    final pages = <MatrixPaginationPage>[];
    final controller = MatrixBackPaginationController(
      engine: engine,
      applyPage: pages.add,
    );
    final state = controller.stateSignal('!room:kite.test');

    final stale = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    expect(state.value.phase, MatrixPaginationPhase.loading);

    controller.cancelInFlight();
    expect(controller.isPaginating('!room:kite.test'), isFalse);
    expect(state.value.phase, MatrixPaginationPhase.idle);

    engine.completePagination(reachedStart: true);
    await stale;
    expect(pages, isEmpty);
    expect(state.value.reachedStart, isFalse);

    final retry = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    expect(engine.paginationCalls, <String>[
      '!room:kite.test',
      '!room:kite.test',
    ]);
    engine.completePagination(reachedStart: true);
    await retry;

    expect(pages, hasLength(1));
    expect(state.value.reachedStart, isTrue);
    await engine.close();
  });

  test('lifecycle cancellation suppresses stale pagination failures', () async {
    final engine = _PaginationFakeMatrixEngine();
    final controller = MatrixBackPaginationController(
      engine: engine,
      applyPage: (_) {},
    );
    final state = controller.stateSignal('!room:kite.test');

    final stale = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    controller.cancelInFlight();
    engine.failPagination(StateError('stale pagination failure'));

    await stale;
    expect(state.value.phase, MatrixPaginationPhase.idle);
    expect(state.value.error, isNull);
    await engine.close();
  });

  test('SDK reached-start state suppresses later edge requests', () async {
    final engine = _PaginationFakeMatrixEngine();
    final pages = <MatrixPaginationPage>[];
    final controller = MatrixBackPaginationController(
      engine: engine,
      applyPage: pages.add,
    );
    final state = controller.stateSignal('!room:kite.test');

    final first = controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    engine.completePagination(reachedStart: true);
    await first;

    expect(state.value.reachedStart, isTrue);
    expect(state.value.hasMoreHistory, isFalse);
    expect(pages, hasLength(1));

    await controller.maybePaginate(
      roomId: '!room:kite.test',
      firstVisibleIndex: 0,
      hasMoreHistory: true,
    );
    expect(engine.paginationCalls, <String>['!room:kite.test']);
    await engine.close();
  });
}

final class _PaginationFakeMatrixEngine implements MatrixEngine {
  _PaginationFakeMatrixEngine({this.syncFailure});

  final Object? syncFailure;
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast();
  final List<String> paginationCalls = <String>[];
  Completer<MatrixPaginationPage>? _pagination;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) {
    paginationCalls.add(roomId);
    final failure = syncFailure;
    if (failure != null) throw failure;
    final pagination = Completer<MatrixPaginationPage>();
    _pagination = pagination;
    return pagination.future;
  }

  void completePagination({bool reachedStart = false}) {
    final roomId = paginationCalls.last;
    _pagination!.complete(
      MatrixPaginationPage(
        roomId: roomId,
        events: const <MatrixTimelineEvent>[],
        reachedStart: reachedStart,
      ),
    );
    _pagination = null;
  }

  void failPagination(Object error) {
    _pagination!.completeError(error, StackTrace.current);
    _pagination = null;
  }

  Future<void> close() => _sync.close();
}
