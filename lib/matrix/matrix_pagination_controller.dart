import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:signals/signals.dart';

enum MatrixPaginationPhase { idle, loading, failed }

final class MatrixPaginationState {
  const MatrixPaginationState.idle({this.reachedStart = false})
    : phase = MatrixPaginationPhase.idle,
      error = null,
      stackTrace = null;

  const MatrixPaginationState.loading({this.reachedStart = false})
    : phase = MatrixPaginationPhase.loading,
      error = null,
      stackTrace = null;

  MatrixPaginationState.failed(
    this.error,
    this.stackTrace, {
    this.reachedStart = false,
  }) : phase = MatrixPaginationPhase.failed;

  final MatrixPaginationPhase phase;
  final Object? error;
  final StackTrace? stackTrace;
  final bool reachedStart;

  bool get hasMoreHistory => !reachedStart;
}

final class MatrixBackPaginationController {
  MatrixBackPaginationController({
    required this.engine,
    required this.applyPage,
    this.edgeThreshold = 8,
  });

  final MatrixEngine engine;
  final void Function(MatrixPaginationPage) applyPage;
  final int edgeThreshold;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, Signal<MatrixPaginationState>> _states =
      <String, Signal<MatrixPaginationState>>{};
  int _generation = 0;

  bool isPaginating(String roomId) => _inFlight.containsKey(roomId);

  ReadonlySignal<MatrixPaginationState> stateSignal(String roomId) {
    return _stateSignal(roomId);
  }

  Signal<MatrixPaginationState> _stateSignal(String roomId) {
    return _states.putIfAbsent(
      roomId,
      () => signal<MatrixPaginationState>(const MatrixPaginationState.idle()),
    );
  }

  void clearFailure(String roomId) {
    if (isPaginating(roomId)) return;
    final state = _states[roomId];
    if (state?.value.phase == MatrixPaginationPhase.failed) {
      state!.value = MatrixPaginationState.idle(
        reachedStart: state.value.reachedStart,
      );
    }
  }

  void cancelInFlight() {
    if (_inFlight.isEmpty) return;
    _generation += 1;
    _inFlight.clear();
    batch(() {
      for (final state in _states.values) {
        if (state.value.phase != MatrixPaginationPhase.loading) continue;
        state.value = MatrixPaginationState.idle(
          reachedStart: state.value.reachedStart,
        );
      }
    });
  }

  Future<void> maybePaginate({
    required String roomId,
    required int firstVisibleIndex,
    required bool hasMoreHistory,
  }) {
    final state = _stateSignal(roomId);
    if (!hasMoreHistory ||
        state.value.reachedStart ||
        firstVisibleIndex > edgeThreshold) {
      return Future<void>.value();
    }

    final existing = _inFlight[roomId];
    if (existing != null) return existing;

    state.value = MatrixPaginationState.loading(
      reachedStart: state.value.reachedStart,
    );

    final pagination = _paginate(roomId, state, _generation);
    _inFlight[roomId] = pagination;
    return pagination.whenComplete(() {
      if (identical(_inFlight[roomId], pagination)) {
        _inFlight.remove(roomId);
      }
    });
  }

  Future<void> _paginate(
    String roomId,
    Signal<MatrixPaginationState> state,
    int generation,
  ) async {
    try {
      final page = await engine.paginateBackwards(roomId);
      if (generation != _generation) return;
      if (page.roomId != roomId) {
        throw StateError('Matrix pagination room mismatch');
      }
      batch(() {
        applyPage(page);
        state.value = MatrixPaginationState.idle(
          reachedStart: page.reachedStart,
        );
      });
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      state.value = MatrixPaginationState.failed(
        error,
        stackTrace,
        reachedStart: state.value.reachedStart,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
