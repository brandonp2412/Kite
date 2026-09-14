import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';

void main() {
  test(
    'pagination exposes leaf loading state and coalesces requests',
    () async {
      final engine = _PaginationFakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
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
      await engine.close();
    },
  );

  test('pagination failure is observable, clearable, and retryable', () async {
    final engine = _PaginationFakeMatrixEngine();
    final controller = MatrixBackPaginationController(engine: engine);
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

  test(
    'pagination remains idle when history is exhausted or edge is distant',
    () async {
      final engine = _PaginationFakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
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
}

final class _PaginationFakeMatrixEngine implements MatrixEngine {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast();
  final List<String> paginationCalls = <String>[];
  Completer<void>? _pagination;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> paginateBackwards(String roomId) {
    paginationCalls.add(roomId);
    final pagination = Completer<void>();
    _pagination = pagination;
    return pagination.future;
  }

  void completePagination() {
    _pagination!.complete();
    _pagination = null;
  }

  void failPagination(Object error) {
    _pagination!.completeError(error, StackTrace.current);
    _pagination = null;
  }

  Future<void> close() => _sync.close();
}
