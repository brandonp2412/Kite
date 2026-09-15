import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_transport.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  Map<String, String?> payload({
    required String id,
    required String kind,
    String accountId = 'work',
    String roomId = '!team:example.org',
    String? eventId,
    String? threadRootEventId,
    String? callId,
  }) => <String, String?>{
    'notification_id': id,
    'kind': kind,
    'account_id': accountId,
    'room_id': roomId,
    'event_id': ?eventId,
    'thread_root_event_id': ?threadRootEventId,
    'call_id': ?callId,
  };

  test(
    'FCM and background sources share one ordered account-safe ingress path',
    () async {
      final accepted = <NotificationIngressResult>[];
      final accounts = FakeNotificationIngressAccountPort(<String>['work']);
      final fcm = FakeNotificationPayloadSource();
      final background = FakeNotificationPayloadSource();
      addTearDown(fcm.close);
      addTearDown(background.close);
      final binding = NotificationTransportBinding(
        ingress: NotificationIngressCoordinator(
          accounts: accounts,
          onAccepted: (result) async => accepted.add(result),
        ),
        fcm: fcm,
        backgroundSync: background,
      );
      addTearDown(binding.stop);

      binding.start();
      binding.start();
      fcm.emit(payload(id: 'mention', kind: 'mention', eventId: r'$mention'));
      background.emit(
        payload(id: 'call', kind: 'call', callId: 'matrix-rtc-session'),
      );
      await binding.flush();

      expect(binding.isStarted, isTrue);
      expect(accepted, hasLength(2));
      expect(accepted[0].transport, NotificationIngressTransport.fcm);
      expect(
        accepted[1].transport,
        NotificationIngressTransport.backgroundSync,
      );
      expect(accepted.map((result) => result.notification!.id), <String>[
        'mention',
        'call',
      ]);
      expect(accounts.queries, <String>['work', 'work']);
    },
  );

  test(
    'malformed and signed-out account payloads never reach delivery',
    () async {
      final accepted = <NotificationIngressResult>[];
      final fcm = FakeNotificationPayloadSource();
      addTearDown(fcm.close);
      final accounts = FakeNotificationIngressAccountPort(<String>['work']);
      final binding = NotificationTransportBinding(
        ingress: NotificationIngressCoordinator(
          accounts: accounts,
          onAccepted: (result) async => accepted.add(result),
        ),
        fcm: fcm,
      );
      addTearDown(binding.stop);

      binding.start();
      fcm.emit(
        payload(id: 'malformed', kind: 'message', eventId: 'not-an-event-id'),
      );
      fcm.emit(
        payload(id: 'signed-out', kind: 'invite', accountId: 'signed-out'),
      );
      await binding.flush();

      expect(accepted, isEmpty);
      expect(accounts.queries, <String>['signed-out']);
    },
  );

  test('transport failures are isolated and later payloads continue', () async {
    final accepted = <String>[];
    final failures = <(NotificationIngressTransport, Object)>[];
    final background = FakeNotificationPayloadSource();
    addTearDown(background.close);
    var failNextDelivery = true;
    final binding = NotificationTransportBinding(
      ingress: NotificationIngressCoordinator(
        accounts: FakeNotificationIngressAccountPort(<String>['work']),
        onAccepted: (result) async {
          if (failNextDelivery) {
            failNextDelivery = false;
            throw StateError('delivery unavailable');
          }
          accepted.add(result.notification!.id);
        },
      ),
      backgroundSync: background,
      onError: (transport, error, _) => failures.add((transport, error)),
    );
    addTearDown(binding.stop);

    binding.start();
    background.emit(payload(id: 'first', kind: 'invite'));
    background.emit(payload(id: 'second', kind: 'invite'));
    background.emitError(StateError('source unavailable'));
    await binding.flush();

    expect(accepted, <String>['second']);
    expect(failures, hasLength(2));
    expect(
      failures.map((failure) => failure.$1).toSet(),
      <NotificationIngressTransport>{
        NotificationIngressTransport.backgroundSync,
      },
    );
  });

  test(
    'stopping cancels source subscriptions and drains queued work',
    () async {
      final accepted = <String>[];
      final fcm = FakeNotificationPayloadSource();
      addTearDown(fcm.close);
      final binding = NotificationTransportBinding(
        ingress: NotificationIngressCoordinator(
          accounts: FakeNotificationIngressAccountPort(<String>['work']),
          onAccepted: (result) async => accepted.add(result.notification!.id),
        ),
        fcm: fcm,
      );

      binding.start();
      fcm.emit(payload(id: 'before-stop', kind: 'invite'));
      await binding.stop();
      fcm.emit(payload(id: 'after-stop', kind: 'invite'));
      await Future<void>.delayed(Duration.zero);

      expect(binding.isStarted, isFalse);
      expect(accepted, <String>['before-stop']);
    },
  );
}
