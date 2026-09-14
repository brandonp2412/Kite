import 'package:flutter_test/flutter_test.dart';
import 'package:kite/testing/deterministic_adapters.dart';

void main() {
  test('deterministic integration adapters are reproducible', () async {
    final adapters = DeterministicIntegrationTestAdapters.standard();
    addTearDown(adapters.dispose);

    expect(adapters.clock.now(), DateTime.utc(2026, 1, 1, 12));
    adapters.clock.advance(const Duration(seconds: 5));
    expect(adapters.clock.now(), DateTime.utc(2026, 1, 1, 12, 0, 5));

    expect(adapters.ids.nextId('event'), 'event-1');
    expect(adapters.ids.nextId('event'), 'event-2');
    expect(adapters.ids.nextId('txn'), 'txn-1');

    final firstImage = adapters.imageFixture();
    final secondImage = adapters.imageFixture();
    expect(firstImage, orderedEquals(secondImage));
    firstImage[0] = 0;
    expect(secondImage.first, 137);
  });

  test('permission and connectivity adapters are deterministic', () async {
    final adapters = DeterministicIntegrationTestAdapters.standard();
    addTearDown(adapters.dispose);

    adapters.permissions.set(TestPermission.camera, PermissionState.granted);
    expect(
      await adapters.permissions.request(TestPermission.camera),
      PermissionState.granted,
    );
    expect(adapters.permissions.requests, <TestPermission>[
      TestPermission.camera,
    ]);

    final changes = <ConnectivityState>[];
    final subscription = adapters.connectivity.changes.listen(changes.add);
    addTearDown(subscription.cancel);

    adapters.connectivity.set(ConnectivityState.offline);
    adapters.connectivity.set(ConnectivityState.offline);
    adapters.connectivity.set(ConnectivityState.online);

    expect(changes, <ConnectivityState>[
      ConnectivityState.offline,
      ConnectivityState.online,
    ]);
  });

  test('fake Matrix event streams preserve deterministic order', () async {
    final adapters = DeterministicIntegrationTestAdapters.standard();
    addTearDown(adapters.dispose);
    final events = adapters.matrixEvents<String>();
    addTearDown(events.close);

    final received = <String>[];
    final subscription = events.stream.listen(received.add);
    addTearDown(subscription.cancel);

    events.emit('room-1:event-1');
    events.emit('room-1:event-2');
    events.emit('room-2:event-1');

    expect(received, <String>[
      'room-1:event-1',
      'room-1:event-2',
      'room-2:event-1',
    ]);
  });
}
