import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_runtime_bindings.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MatrixBoundaryEngine', () {
    test('rejects SDK boundaries without audited encryption', () {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.encryptedPersistentStore,
        },
      );

      expect(
        () => MatrixBoundaryEngine(boundary: boundary, store: _store),
        throwsA(isA<MatrixSdkContractException>()),
      );
      expect(boundary.openCalls, 0);
    });

    test('opens encrypted store once and delegates sync lifecycle', () async {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
          MatrixSdkCapability.backPagination,
        },
      );
      final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);

      await engine.start();
      await engine.start();
      await engine.paginateBackwards('!alpha:kite.test');
      await engine.stop();
      await engine.stop();
      await engine.close();

      expect(boundary.openCalls, 1);
      expect(boundary.openedStore, same(_store));
      expect(boundary.startCalls, 1);
      expect(boundary.stopCalls, 1);
      expect(boundary.paginatedRooms, <String>['!alpha:kite.test']);
      expect(boundary.closeCalls, 1);
    });
  });

  test(
    'runtime sync follows foreground and connectivity without blanking data',
    () async {
      final engine = _FakeMatrixEngine();
      final applied = <MatrixSyncBatch>[];
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: applied.add,
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );

      await runtime.start();
      expect(engine.startCalls, 1);
      expect(applied.single.cursor, 'start-1');

      await runtime.updateActivity(MatrixAppActivity.background);
      expect(engine.stopCalls, 1);

      await runtime.updateNetworkState(MatrixNetworkState.offline);
      await runtime.updateActivity(MatrixAppActivity.foreground);
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 1);
      expect(applied.single.cursor, 'start-1');

      await runtime.updateNetworkState(MatrixNetworkState.online);
      expect(engine.startCalls, 2);
      expect(applied.map((batch) => batch.cursor), <String>[
        'start-1',
        'start-2',
      ]);

      await runtime.stop();
      expect(engine.stopCalls, 2);
      await engine.close();
    },
  );

  test('runtime recovers cleanly when an engine start attempt fails', () async {
    final engine = _FakeMatrixEngine(startFailuresRemaining: 1);
    final runtime = MatrixRuntimeCoordinator(
      engine: engine,
      applyBatch: (_) {},
      initialActivity: MatrixAppActivity.foreground,
      initialNetworkState: MatrixNetworkState.online,
    );

    await expectLater(runtime.start(), throwsA(isA<StateError>()));
    expect(runtime.isSyncing, isFalse);
    expect(engine.startCalls, 1);

    await runtime.start();
    expect(runtime.isSyncing, isTrue);
    expect(engine.startCalls, 2);

    await runtime.stop();
    await engine.close();
  });

  test('Flutter lifecycle states map to deterministic sync activity', () async {
    final engine = _FakeMatrixEngine();
    final applied = <MatrixSyncBatch>[];
    final runtime = MatrixRuntimeCoordinator(
      engine: engine,
      applyBatch: applied.add,
      initialActivity: MatrixAppActivity.foreground,
      initialNetworkState: MatrixNetworkState.online,
    );
    final binding = MatrixLifecycleBinding(runtime);

    await runtime.start();
    await binding.handleLifecycleState(AppLifecycleState.inactive);
    await binding.handleLifecycleState(AppLifecycleState.hidden);
    await binding.handleLifecycleState(AppLifecycleState.paused);
    await binding.handleLifecycleState(AppLifecycleState.detached);
    expect(runtime.isSyncing, isFalse);
    expect(engine.stopCalls, 1);

    await binding.handleLifecycleState(AppLifecycleState.resumed);
    expect(runtime.isSyncing, isTrue);
    expect(engine.startCalls, 2);
    expect(applied.map((batch) => batch.cursor), <String>[
      'start-1',
      'start-2',
    ]);

    await runtime.stop();
    await engine.close();
  });

  test(
    'connectivity binding forwards loss and recovery without cache reset',
    () async {
      final engine = _FakeMatrixEngine();
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!alpha:kite.test',
              displayName: 'Alpha cached',
              lastActivity: DateTime.utc(2026, 9, 14, 12),
              streamPosition: 7,
            ),
          ],
        ),
      );
      final roomOrderBefore = cache.roomOrder.value;
      final summaryBefore = cache.roomSummarySignal('!alpha:kite.test').value;
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: cache.applySync,
        initialActivity: MatrixAppActivity.foreground,
        initialNetworkState: MatrixNetworkState.online,
      );
      final changes = StreamController<MatrixNetworkState>.broadcast(
        sync: true,
      );
      final binding = MatrixConnectivityBinding(
        runtime,
        MatrixNetworkState.online,
        changes.stream,
      );

      await runtime.start();
      await binding.attach();
      changes.add(MatrixNetworkState.offline);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.isSyncing, isFalse);
      expect(cache.lastSyncCursor, 'start-1');
      expect(identical(cache.roomOrder.value, roomOrderBefore), isTrue);
      expect(
        identical(
          cache.roomSummarySignal('!alpha:kite.test').value,
          summaryBefore,
        ),
        isTrue,
      );

      changes.add(MatrixNetworkState.online);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.isSyncing, isTrue);
      expect(cache.lastSyncCursor, 'start-2');
      expect(identical(cache.roomOrder.value, roomOrderBefore), isTrue);
      expect(
        identical(
          cache.roomSummarySignal('!alpha:kite.test').value,
          summaryBefore,
        ),
        isTrue,
      );

      await binding.detach();
      await changes.close();
      await runtime.stop();
      await engine.close();
    },
  );

  test(
    'near-edge pagination coalesces one in-flight request per room',
    () async {
      final engine = _FakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
        edgeThreshold: 5,
      );

      await controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 6,
        hasMoreHistory: true,
      );
      await controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: false,
      );
      expect(engine.paginationCalls, isEmpty);

      final first = controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 5,
        hasMoreHistory: true,
      );
      final second = controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 1,
        hasMoreHistory: true,
      );

      expect(engine.paginationCalls, <String>['!alpha:kite.test']);
      expect(controller.isPaginating('!alpha:kite.test'), isTrue);

      engine.completePagination();
      await Future.wait(<Future<void>>[first, second]);
      expect(controller.isPaginating('!alpha:kite.test'), isFalse);

      final third = controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(engine.paginationCalls, <String>[
        '!alpha:kite.test',
        '!alpha:kite.test',
      ]);
      engine.completePagination();
      await third;
      await engine.close();
    },
  );
}

const _store = MatrixSdkStoreConfiguration(
  accountId: '@kite:kite.test',
  storePath: '/encrypted/matrix-store',
  encryptionKeyId: 'platform-key-alias',
);

final class _FakeSdkBoundary implements MatrixSdkBoundary {
  _FakeSdkBoundary({required this.capabilities});

  @override
  final Set<MatrixSdkCapability> capabilities;

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);
  int openCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;
  MatrixSdkStoreConfiguration? openedStore;
  final List<String> paginatedRooms = <String>[];

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openCalls += 1;
    openedStore = store;
  }

  @override
  Future<void> startSync() async {
    startCalls += 1;
  }

  @override
  Future<void> stopSync() async {
    stopCalls += 1;
  }

  @override
  Future<void> paginateBackwards(String roomId) async {
    paginatedRooms.add(roomId);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _sync.close();
  }
}

final class _FakeMatrixEngine implements MatrixEngine {
  _FakeMatrixEngine({this.startFailuresRemaining = 0});

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);
  final List<String> paginationCalls = <String>[];
  Completer<void>? _pagination;
  int startFailuresRemaining;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
    if (startFailuresRemaining > 0) {
      startFailuresRemaining -= 1;
      throw StateError('deterministic start failure');
    }
    _sync.add(
      MatrixSyncBatch(
        cursor: 'start-$startCalls',
        rooms: const <MatrixRoomDelta>[],
      ),
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

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

  Future<void> close() => _sync.close();
}
