import 'dart:async';

import 'package:kite/matrix/matrix_engine.dart';

final class MatrixBackPaginationController {
  MatrixBackPaginationController({
    required this.engine,
    this.edgeThreshold = 8,
  });

  final MatrixEngine engine;
  final int edgeThreshold;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  bool isPaginating(String roomId) => _inFlight.containsKey(roomId);

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

    final pagination = engine.paginateBackwards(roomId);
    _inFlight[roomId] = pagination;
    return pagination.whenComplete(() {
      if (identical(_inFlight[roomId], pagination)) {
        _inFlight.remove(roomId);
      }
    });
  }
}
