import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';
import 'package:signals/signals.dart';

enum MatrixPaginationPhase { idle, loading, failed }

final class MatrixPaginationState {
  const MatrixPaginationState._(this.phase, this.error, this.stackTrace);

  const MatrixPaginationState.idle()
    : this._(MatrixPaginationPhase.idle, null, null);

  const MatrixPaginationState.loading()
    : this._(MatrixPaginationPhase.loading, null, null);

  MatrixPaginationState.failed(Object error, StackTrace stackTrace)
    : this._(MatrixPaginationPhase.failed, error, stackTrace);

  final MatrixPaginationPhase phase;
  final Object? error;
  final StackTrace? stackTrace;
}

final class MatrixBackPaginationController {
  MatrixBackPaginationController({
    required this.engine,
    this.edgeThreshold = 8,
  });

  final MatrixEngine engine;
  final int edgeThreshold;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, Signal<MatrixPaginationState>> _states =
      <String, Signal<MatrixPaginationState>>{};

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
      state!.value = const MatrixPaginationState.idle();
    }
  }

  Future<void> maybePaginate({
    required String roomId,
    required int firstVisibleIndex,
    required bool hasMoreHistory,
  }) {
    if (!hasMoreHistory || firstVisibleIndex > edgeThreshold) {
      return Future<void>.value();
    }

    final existing = _inFlight[roomId];
    if (existing != null) return existing;

    final state = _stateSignal(roomId);
    state.value = const MatrixPaginationState.loading();

    late final Future<void> pagination;
    late final Future<void> request;
    try {
      request = engine.paginateBackwards(roomId);
    } catch (error, stackTrace) {
      state.value = MatrixPaginationState.failed(error, stackTrace);
      return Future<void>.error(error, stackTrace);
    }
    pagination = request.then<void>(
      (_) {
        if (identical(_inFlight[roomId], pagination)) {
          state.value = const MatrixPaginationState.idle();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlight[roomId], pagination)) {
          state.value = MatrixPaginationState.failed(error, stackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _inFlight[roomId] = pagination;
    return pagination.whenComplete(() {
      if (identical(_inFlight[roomId], pagination)) {
        _inFlight.remove(roomId);
      }
    });
  }
}
