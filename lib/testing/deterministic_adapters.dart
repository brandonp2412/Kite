import 'dart:async';
import 'dart:typed_data';

abstract interface class Clock {
  DateTime now();
}

final class DeterministicClock implements Clock {
  DeterministicClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

abstract interface class IdGenerator {
  String nextId(String namespace);
}

final class DeterministicIdGenerator implements IdGenerator {
  DeterministicIdGenerator({this.seed = 0});

  final int seed;
  final Map<String, int> _counters = <String, int>{};

  @override
  String nextId(String namespace) {
    final next = (_counters[namespace] ?? seed) + 1;
    _counters[namespace] = next;
    return '$namespace-$next';
  }
}

final class DeterministicImageFixtures {
  DeterministicImageFixtures._();

  static final Uint8List transparentPng1x1 = Uint8List.fromList(<int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    13,
    73,
    68,
    65,
    84,
    8,
    215,
    99,
    248,
    207,
    192,
    240,
    31,
    0,
    5,
    0,
    1,
    255,
    137,
    153,
    61,
    29,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);
}

enum TestPermission { camera, microphone, notifications, photos, location }

enum PermissionState { granted, denied, permanentlyDenied }

abstract interface class PermissionAdapter {
  Future<PermissionState> status(TestPermission permission);
  Future<PermissionState> request(TestPermission permission);
}

final class FakePermissionAdapter implements PermissionAdapter {
  FakePermissionAdapter({Map<TestPermission, PermissionState>? initialStates})
    : _states = <TestPermission, PermissionState>{
        for (final permission in TestPermission.values)
          permission: initialStates?[permission] ?? PermissionState.denied,
      };

  final Map<TestPermission, PermissionState> _states;
  final List<TestPermission> requests = <TestPermission>[];

  void set(TestPermission permission, PermissionState state) {
    _states[permission] = state;
  }

  @override
  Future<PermissionState> request(TestPermission permission) async {
    requests.add(permission);
    return _states[permission]!;
  }

  @override
  Future<PermissionState> status(TestPermission permission) async =>
      _states[permission]!;
}

enum ConnectivityState { online, offline }

abstract interface class ConnectivityAdapter {
  ConnectivityState get current;
  Stream<ConnectivityState> get changes;
}

final class FakeConnectivityAdapter implements ConnectivityAdapter {
  FakeConnectivityAdapter([this._current = ConnectivityState.online]);

  final StreamController<ConnectivityState> _controller =
      StreamController<ConnectivityState>.broadcast(sync: true);
  ConnectivityState _current;

  @override
  ConnectivityState get current => _current;

  @override
  Stream<ConnectivityState> get changes => _controller.stream;

  void set(ConnectivityState state) {
    if (_current == state) return;
    _current = state;
    _controller.add(state);
  }

  Future<void> close() => _controller.close();
}

final class FakeMatrixEventStream<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast(
    sync: true,
  );

  Stream<T> get stream => _controller.stream;

  void emit(T event) => _controller.add(event);

  Future<void> close() => _controller.close();
}

final class DeterministicIntegrationTestAdapters {
  DeterministicIntegrationTestAdapters({
    required this.clock,
    required this.ids,
    required this.permissions,
    required this.connectivity,
  });

  factory DeterministicIntegrationTestAdapters.standard() {
    return DeterministicIntegrationTestAdapters(
      clock: DeterministicClock(DateTime.utc(2026, 1, 1, 12)),
      ids: DeterministicIdGenerator(),
      permissions: FakePermissionAdapter(),
      connectivity: FakeConnectivityAdapter(),
    );
  }

  final DeterministicClock clock;
  final DeterministicIdGenerator ids;
  final FakePermissionAdapter permissions;
  final FakeConnectivityAdapter connectivity;

  FakeMatrixEventStream<T> matrixEvents<T>() => FakeMatrixEventStream<T>();

  Uint8List imageFixture() =>
      Uint8List.fromList(DeterministicImageFixtures.transparentPng1x1);

  Future<void> dispose() => connectivity.close();
}
