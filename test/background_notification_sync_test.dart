import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';

void main() {
  test(
    'notification mode keeps Matrix sync alive while backgrounded',
    () async {
      final engine = _NotificationMatrixEngine();
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: (_) {},
        applyPagination: (_) => true,
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
        syncWhileBackgrounded: true,
      );

      await runtime.start();
      await runtime.updateActivity(MatrixAppActivity.background);

      expect(runtime.isSyncing, isTrue);
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 0);

      await runtime.stop();
      await engine.close();
    },
  );
}

final class _NotificationMatrixEngine implements MatrixEngine {
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    return MatrixPaginationPage(
      roomId: roomId,
      events: const <MatrixTimelineEvent>[],
      reachedStart: true,
    );
  }

  Future<void> close() => _sync.close();
}
