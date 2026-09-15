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

    test('rejects SDK boundaries without incremental sync support', () {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
        },
      );

      expect(
        () => MatrixBoundaryEngine(boundary: boundary, store: _store),
        throwsA(isA<MatrixSdkContractException>()),
      );
      expect(boundary.openCalls, 0);
    });

    test('rejects malformed encrypted store metadata before SDK open', () {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
          MatrixSdkCapability.incrementalSync,
        },
      );

      for (final store in <MatrixSdkStoreConfiguration>[
        const MatrixSdkStoreConfiguration(
          accountId: '',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:kite.test',
          storePath: '',
          encryptionKeyId: 'alice-key',
        ),
        const MatrixSdkStoreConfiguration(
          accountId: '@alice:kite.test',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: '',
        ),
      ]) {
        expect(
          () => MatrixBoundaryEngine(boundary: boundary, store: store),
          throwsArgumentError,
        );
      }
      expect(boundary.openCalls, 0);
    });

    test(
      'rejects unsafe resume cursors before opening the SDK store',
      () async {
        final boundary = _FakeSdkBoundary(
          capabilities: const <MatrixSdkCapability>{
            MatrixSdkCapability.auditedEncryption,
            MatrixSdkCapability.encryptedPersistentStore,
            MatrixSdkCapability.incrementalSync,
          },
        );
        final cursors = <String>['', 'resume\u0000truncated'];

        for (final cursor in cursors) {
          final engine = MatrixBoundaryEngine(
            boundary: boundary,
            store: _store,
            syncConfigurationProvider: () =>
                MatrixSdkSyncConfiguration(resumeFromCursor: cursor),
          );
          await expectLater(engine.start(), throwsArgumentError);
        }

        expect(boundary.openCalls, 0);
        expect(boundary.startCalls, 0);
      },
    );

    test('failed SDK sync start is stopped before retry', () async {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
          MatrixSdkCapability.incrementalSync,
        },
        startFailuresRemaining: 1,
      );
      final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);
      final coordinator = MatrixSyncCoordinator(
        engine: engine,
        applyBatch: (_) {},
      );

      await expectLater(coordinator.start(), throwsStateError);
      expect(boundary.openCalls, 1);
      expect(boundary.startCalls, 1);
      expect(boundary.stopCalls, 1);

      await coordinator.start();
      expect(boundary.openCalls, 1);
      expect(boundary.startCalls, 2);
      expect(boundary.stopCalls, 1);

      await coordinator.stop();
      expect(boundary.stopCalls, 2);
      await engine.close();
      expect(boundary.closeCalls, 1);
    });

    test(
      'back-pagination rejects blank ids and normalizes surrounding space',
      () async {
        final boundary = _FakeSdkBoundary(
          capabilities: const <MatrixSdkCapability>{
            MatrixSdkCapability.auditedEncryption,
            MatrixSdkCapability.encryptedPersistentStore,
            MatrixSdkCapability.incrementalSync,
            MatrixSdkCapability.backPagination,
          },
        );
        final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);

        await expectLater(engine.paginateBackwards('   '), throwsArgumentError);
        expect(boundary.openCalls, 0);

        await engine.paginateBackwards('  !alpha:kite.test  ');
        expect(boundary.paginatedRooms, <String>['!alpha:kite.test']);
        await engine.close();
      },
    );

    test('back-pagination requires explicit SDK capability', () async {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
          MatrixSdkCapability.incrementalSync,
        },
      );
      final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);

      await expectLater(
        engine.paginateBackwards('!alpha:kite.test'),
        throwsA(isA<MatrixSdkContractException>()),
      );
      expect(boundary.openCalls, 0);
    });

    test('opens encrypted store once and delegates sync lifecycle', () async {
      final boundary = _FakeSdkBoundary(
        capabilities: const <MatrixSdkCapability>{
          MatrixSdkCapability.auditedEncryption,
          MatrixSdkCapability.encryptedPersistentStore,
          MatrixSdkCapability.incrementalSync,
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
      expect(boundary.lastSyncConfiguration?.initialRoomListLimit, 200);
      expect(boundary.lastSyncConfiguration?.initialTimelineEventLimit, 1);
      expect(boundary.lastSyncConfiguration?.timelineEventLimit, 20);
      expect(boundary.lastSyncConfiguration?.resumeFromCursor, isNull);
      expect(boundary.stopCalls, 1);
      expect(boundary.paginatedRooms, <String>['!alpha:kite.test']);
      expect(boundary.closeCalls, 1);
    });

    test(
      'initial SDK sync populates the room list then updates leaf state',
      () async {
        final initialRooms = List<MatrixRoomDelta>.generate(200, (index) {
          final roomId = '!room$index:kite.test';
          return MatrixRoomDelta(
            roomId: roomId,
            summary: MatrixRoomSummary(
              roomId: roomId,
              displayName: 'Room $index',
              lastActivity: DateTime.utc(
                2026,
                9,
                15,
                2,
              ).add(Duration(seconds: index)),
              streamPosition: index,
            ),
          );
        });
        final boundary = _FakeSdkBoundary(
          capabilities: const <MatrixSdkCapability>{
            MatrixSdkCapability.auditedEncryption,
            MatrixSdkCapability.encryptedPersistentStore,
            MatrixSdkCapability.incrementalSync,
            MatrixSdkCapability.backPagination,
          },
          startBatch: MatrixSyncBatch(cursor: 'initial', rooms: initialRooms),
        );
        final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);
        final cache = MatrixPresentationCache();
        final sync = MatrixSyncCoordinator(
          engine: engine,
          applyBatch: cache.applySync,
        );

        await sync.start();

        expect(cache.roomOrder.value, hasLength(200));
        expect(cache.roomOrder.value.first, '!room199:kite.test');
        expect(cache.lastSyncCursor, 'initial');
        final orderBefore = cache.roomOrder.value;
        final untouchedBefore = cache
            .roomSummarySignal('!room199:kite.test')
            .value;

        boundary.emit(
          MatrixSyncBatch(
            cursor: 'incremental-1',
            rooms: <MatrixRoomDelta>[
              MatrixRoomDelta(
                roomId: '!room0:kite.test',
                summary: MatrixRoomSummary(
                  roomId: '!room0:kite.test',
                  displayName: 'Room zero renamed',
                  lastActivity: DateTime.utc(2026, 9, 15, 2),
                  streamPosition: 500,
                ),
              ),
            ],
          ),
        );

        expect(cache.lastSyncCursor, 'incremental-1');
        expect(
          cache.roomSummarySignal('!room0:kite.test').value?.displayName,
          'Room zero renamed',
        );
        expect(
          identical(
            cache.roomSummarySignal('!room199:kite.test').value,
            untouchedBefore,
          ),
          isTrue,
        );
        expect(identical(cache.roomOrder.value, orderBefore), isTrue);

        await sync.stop();
        await engine.close();
      },
    );

    test(
      'back-pagination flows through the SDK boundary into the cache',
      () async {
        const roomId = '!alpha:kite.test';
        final boundary = _FakeSdkBoundary(
          capabilities: const <MatrixSdkCapability>{
            MatrixSdkCapability.auditedEncryption,
            MatrixSdkCapability.encryptedPersistentStore,
            MatrixSdkCapability.incrementalSync,
            MatrixSdkCapability.backPagination,
          },
          paginationPages: <String, MatrixPaginationPage>{
            roomId: MatrixPaginationPage(
              roomId: roomId,
              events: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$older:kite.test',
                  roomId: roomId,
                  senderId: '@alice:kite.test',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 15, 1),
                  streamPosition: 1,
                ),
              ],
              reachedStart: true,
            ),
          },
        );
        final engine = MatrixBoundaryEngine(boundary: boundary, store: _store);
        final cache = MatrixPresentationCache(
          initialSnapshot: MatrixPresentationSnapshot(
            rooms: <MatrixRoomSummary>[
              MatrixRoomSummary(
                roomId: roomId,
                displayName: 'Alpha',
                lastActivity: DateTime.utc(2026, 9, 15, 2),
                streamPosition: 2,
              ),
            ],
            timelines: <String, List<MatrixTimelineEvent>>{
              roomId: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$newer:kite.test',
                  roomId: roomId,
                  senderId: '@bob:kite.test',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 15, 2),
                  streamPosition: 2,
                ),
              ],
            },
          ),
        );
        final roomOrderBefore = cache.roomOrder.value;
        final summaryBefore = cache.roomSummarySignal(roomId).value;
        final sync = MatrixSyncCoordinator(
          engine: engine,
          applyBatch: cache.applySync,
        );

        await sync.start();
        final page = await engine.paginateBackwards(roomId);
        cache.applyPagination(page);

        expect(boundary.paginatedRooms, <String>[roomId]);
        expect(page.reachedStart, isTrue);
        expect(cache.lastSyncCursor, isNull);
        expect(
          cache.timelineSignal(roomId).value.map((event) => event.eventId),
          <String>[r'$older:kite.test', r'$newer:kite.test'],
        );
        expect(identical(cache.roomOrder.value, roomOrderBefore), isTrue);
        expect(
          identical(cache.roomSummarySignal(roomId).value, summaryBefore),
          isTrue,
        );

        await sync.stop();
        await engine.close();
      },
    );
  });

  test(
    'runtime sync follows foreground and connectivity without blanking data',
    () async {
      final engine = _FakeMatrixEngine();
      final applied = <MatrixSyncBatch>[];
      final runtime = MatrixRuntimeCoordinator(
        engine: engine,
        applyBatch: applied.add,
        applyPagination: (_) {},
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
      applyPagination: (_) {},
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
      applyPagination: (_) {},
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

  testWidgets('failed initial lifecycle update leaves observer detached', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final runtime = _FailingActivityRuntime();
    final binding = MatrixLifecycleBinding(runtime, binding: tester.binding);

    await expectLater(binding.attach(), throwsA(isA<StateError>()));

    expect(binding.isAttached, isFalse);
    expect(runtime.states, <MatrixAppActivity>[MatrixAppActivity.foreground]);
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
        applyPagination: cache.applyPagination,
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
    'connectivity binding observes changes while initial state is applying',
    () async {
      final runtime = _ControlledConnectivityRuntime();
      final changes = StreamController<MatrixNetworkState>.broadcast(
        sync: true,
      );
      final binding = MatrixConnectivityBinding(
        runtime,
        MatrixNetworkState.online,
        changes.stream,
      );

      final attach = binding.attach();
      expect(binding.isAttached, isTrue);
      expect(runtime.states, <MatrixNetworkState>[MatrixNetworkState.online]);

      changes.add(MatrixNetworkState.offline);
      expect(runtime.states, <MatrixNetworkState>[
        MatrixNetworkState.online,
        MatrixNetworkState.offline,
      ]);

      runtime.completeInitialUpdate();
      await attach;
      await binding.detach();
      await changes.close();
    },
  );

  test('failed initial connectivity update leaves binding detached', () async {
    final runtime = _ControlledConnectivityRuntime();
    final changes = StreamController<MatrixNetworkState>.broadcast(sync: true);
    final binding = MatrixConnectivityBinding(
      runtime,
      MatrixNetworkState.online,
      changes.stream,
    );

    final attach = binding.attach();
    runtime.failInitialUpdate(StateError('deterministic connectivity failure'));

    await expectLater(attach, throwsA(isA<StateError>()));
    expect(binding.isAttached, isFalse);

    changes.add(MatrixNetworkState.offline);
    expect(runtime.states, <MatrixNetworkState>[MatrixNetworkState.online]);
    await changes.close();
  });

  test(
    'near-edge pagination coalesces one in-flight request per room',
    () async {
      final engine = _FakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
        applyPage: (_) {},
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

  test(
    'failed near-edge pagination clears in-flight state for retry',
    () async {
      final engine = _FakeMatrixEngine();
      final controller = MatrixBackPaginationController(
        engine: engine,
        applyPage: (_) {},
      );

      final failed = controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(controller.isPaginating('!alpha:kite.test'), isTrue);
      engine.failPagination();
      await expectLater(failed, throwsA(isA<StateError>()));
      expect(controller.isPaginating('!alpha:kite.test'), isFalse);

      final retry = controller.maybePaginate(
        roomId: '!alpha:kite.test',
        firstVisibleIndex: 0,
        hasMoreHistory: true,
      );
      expect(engine.paginationCalls, <String>[
        '!alpha:kite.test',
        '!alpha:kite.test',
      ]);
      engine.completePagination();
      await retry;
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
  _FakeSdkBoundary({
    required this.capabilities,
    this.startBatch,
    this.paginationPages = const <String, MatrixPaginationPage>{},
    this.startFailuresRemaining = 0,
  });

  @override
  final Set<MatrixSdkCapability> capabilities;
  final MatrixSyncBatch? startBatch;
  final Map<String, MatrixPaginationPage> paginationPages;
  int startFailuresRemaining;

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);
  int openCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;
  MatrixSdkStoreConfiguration? openedStore;
  MatrixSdkSyncConfiguration? lastSyncConfiguration;
  final List<String> paginatedRooms = <String>[];

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openCalls += 1;
    openedStore = store;
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) async {
    startCalls += 1;
    lastSyncConfiguration = configuration;
    if (startFailuresRemaining > 0) {
      startFailuresRemaining -= 1;
      throw StateError('deterministic SDK sync start failure');
    }
    final batch = startBatch;
    if (batch != null) _sync.add(batch);
  }

  @override
  Future<void> stopSync() async {
    stopCalls += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    paginatedRooms.add(roomId);
    return paginationPages[roomId] ??
        MatrixPaginationPage(
          roomId: roomId,
          events: const <MatrixTimelineEvent>[],
          reachedStart: false,
        );
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _sync.close();
  }

  void emit(MatrixSyncBatch batch) => _sync.add(batch);
}

final class _FailingActivityRuntime implements MatrixActivityRuntime {
  final List<MatrixAppActivity> states = <MatrixAppActivity>[];

  @override
  Future<void> updateActivity(MatrixAppActivity activity) async {
    states.add(activity);
    throw StateError('deterministic lifecycle failure');
  }
}

final class _ControlledConnectivityRuntime
    implements MatrixConnectivityRuntime {
  final Completer<void> _initialUpdate = Completer<void>();
  final List<MatrixNetworkState> states = <MatrixNetworkState>[];
  var _updateCount = 0;

  @override
  Future<void> updateNetworkState(MatrixNetworkState state) {
    states.add(state);
    _updateCount += 1;
    if (_updateCount == 1) return _initialUpdate.future;
    return Future<void>.value();
  }

  void completeInitialUpdate() => _initialUpdate.complete();

  void failInitialUpdate(Object error) => _initialUpdate.completeError(error);
}

final class _FakeMatrixEngine implements MatrixEngine {
  _FakeMatrixEngine({this.startFailuresRemaining = 0});

  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);
  final List<String> paginationCalls = <String>[];
  Completer<MatrixPaginationPage>? _pagination;
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
  Future<MatrixPaginationPage> paginateBackwards(String roomId) {
    paginationCalls.add(roomId);
    final pagination = Completer<MatrixPaginationPage>();
    _pagination = pagination;
    return pagination.future;
  }

  void completePagination({bool reachedStart = false}) {
    _pagination!.complete(
      MatrixPaginationPage(
        roomId: paginationCalls.last,
        events: const <MatrixTimelineEvent>[],
        reachedStart: reachedStart,
      ),
    );
    _pagination = null;
  }

  void failPagination() {
    _pagination!.completeError(StateError('deterministic pagination failure'));
    _pagination = null;
  }

  Future<void> close() => _sync.close();
}
