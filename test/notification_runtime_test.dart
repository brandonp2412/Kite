import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/notification_runtime.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  test(
    'FCM and background sync resolve exact message mention and invite targets',
    () async {
      final fcm = FakeNotificationPayloadSource();
      final background = FakeNotificationPayloadSource();
      addTearDown(fcm.close);
      addTearDown(background.close);
      final repository = FakeNotificationRepository();
      final delivery = FakeNotificationDeliveryPort();
      final resolver = FakeNotificationEventResolver();
      final runtime = NotificationRuntime(
        accounts: FakeNotificationIngressAccountPort(const <String>['work']),
        resolver: resolver,
        dispatch: NotificationDispatchCoordinator(
          notifications: repository,
          delivery: NotificationDeliveryCoordinator(
            privacy: FakeNotificationPrivacyPort(),
            delivery: delivery,
          ),
        ),
        fcm: fcm,
        backgroundSync: background,
      );

      for (final fixture
          in <
            ({
              String id,
              String kind,
              String? eventId,
              MatrixNotificationEventKind resolvedKind,
              KiteNotificationKind notificationKind,
            })
          >[
            (
              id: 'message-1',
              kind: 'message',
              eventId: r'$message',
              resolvedKind: MatrixNotificationEventKind.message,
              notificationKind: KiteNotificationKind.message,
            ),
            (
              id: 'mention-1',
              kind: 'mention',
              eventId: r'$mention',
              resolvedKind: MatrixNotificationEventKind.mention,
              notificationKind: KiteNotificationKind.mention,
            ),
            (
              id: 'invite-1',
              kind: 'invite',
              eventId: null,
              resolvedKind: MatrixNotificationEventKind.invite,
              notificationKind: KiteNotificationKind.invite,
            ),
          ]) {
        final destination = fixture.eventId == null
            ? const AppDestination.room(
                accountId: 'work',
                roomId: '!team:example.org',
              )
            : AppDestination.event(
                accountId: 'work',
                roomId: '!team:example.org',
                eventId: fixture.eventId!,
              );
        final notification = KiteNotification(
          id: fixture.id,
          kind: fixture.notificationKind,
          destination: destination,
        );
        resolver.eventsByRoutingId[notification.routingId] =
            MatrixNotificationEvent(
              id: fixture.id,
              kind: fixture.resolvedKind,
              accountId: 'work',
              roomId: '!team:example.org',
              eventId: fixture.eventId,
              title: fixture.kind,
              body: '${fixture.kind} body',
            );
      }

      runtime.start();
      fcm.emit(
        _payload(id: 'message-1', kind: 'message', eventId: r'$message'),
      );
      background.emit(
        _payload(id: 'mention-1', kind: 'mention', eventId: r'$mention'),
      );
      fcm.emit(_payload(id: 'invite-1', kind: 'invite'));
      await runtime.flush();

      expect(runtime.isStarted, isTrue);
      expect(
        resolver.resolutions.map((notification) => notification.kind),
        <KiteNotificationKind>[
          KiteNotificationKind.message,
          KiteNotificationKind.mention,
          KiteNotificationKind.invite,
        ],
      );
      expect(delivery.shown.map((presentation) => presentation.body), <String>[
        'message body',
        'mention body',
        'invite body',
      ]);
      expect(repository.activeForAccount('work'), hasLength(3));

      await runtime.stop();
      expect(runtime.isStarted, isFalse);
    },
  );

  test(
    'runtime preserves thread call and account identity across transports',
    () async {
      final fcm = FakeNotificationPayloadSource();
      final background = FakeNotificationPayloadSource();
      addTearDown(fcm.close);
      addTearDown(background.close);
      final repository = FakeNotificationRepository();
      final delivery = FakeNotificationDeliveryPort();
      final resolver = FakeNotificationEventResolver();
      final callHandOffs = <KiteNotification>[];
      final runtime = NotificationRuntime(
        accounts: FakeNotificationIngressAccountPort(const <String>[
          'work',
          'personal',
        ]),
        resolver: resolver,
        dispatch: NotificationDispatchCoordinator(
          notifications: repository,
          delivery: NotificationDeliveryCoordinator(
            privacy: FakeNotificationPrivacyPort(),
            delivery: delivery,
          ),
          onCallNotification: (notification) async {
            callHandOffs.add(notification);
            return true;
          },
        ),
        fcm: fcm,
        backgroundSync: background,
      );
      const thread = KiteNotification(
        id: 'shared-id',
        kind: KiteNotificationKind.thread,
        destination: AppDestination.thread(
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$reply',
          threadRootEventId: r'$root',
        ),
      );
      const call = KiteNotification(
        id: 'shared-id',
        kind: KiteNotificationKind.call,
        destination: AppDestination.call(
          accountId: 'personal',
          roomId: '!calls:example.org',
          callId: 'rtc-personal',
        ),
      );
      resolver.eventsByRoutingId[thread.routingId] =
          const MatrixNotificationEvent(
            id: 'shared-id',
            kind: MatrixNotificationEventKind.thread,
            accountId: 'work',
            roomId: '!team:example.org',
            eventId: r'$reply',
            threadRootEventId: r'$root',
            title: 'Thread reply',
            body: 'Work thread body',
          );
      resolver.eventsByRoutingId[call.routingId] =
          const MatrixNotificationEvent(
            id: 'shared-id',
            kind: MatrixNotificationEventKind.call,
            accountId: 'personal',
            roomId: '!calls:example.org',
            callId: 'rtc-personal',
            title: 'Incoming call',
            body: 'Personal call body',
          );

      runtime.start();
      fcm.emit(
        _payload(
          id: 'shared-id',
          kind: 'thread',
          accountId: 'work',
          eventId: r'$reply',
          threadRootEventId: r'$root',
        ),
      );
      background.emit(
        _payload(
          id: 'shared-id',
          kind: 'call',
          accountId: 'personal',
          roomId: '!calls:example.org',
          callId: 'rtc-personal',
        ),
      );
      await runtime.flush();

      expect(
        resolver.resolutions.map((notification) => notification.routingId),
        <String>[thread.routingId, call.routingId],
      );
      expect(
        resolver.resolutions.map((notification) => notification.destination),
        <AppDestination>[thread.destination, call.destination],
      );
      expect(
        repository.notification(thread.routingId)?.destination,
        thread.destination,
      );
      expect(
        repository.notification(call.routingId)?.destination,
        call.destination,
      );
      expect(
        repository.activeForAccount('work').single.kind,
        KiteNotificationKind.thread,
      );
      expect(
        repository.activeForAccount('personal').single.kind,
        KiteNotificationKind.call,
      );
      expect(callHandOffs.single.destination, call.destination);
      expect(delivery.shown.map((item) => item.body), <String>[
        'Work thread body',
        'Personal call body',
      ]);
      expect(delivery.shown.last.requestsIncomingCallSurface, isTrue);

      await runtime.stop();
    },
  );

  test('runtime isolates unknown accounts and transport failures', () async {
    final fcm = FakeNotificationPayloadSource();
    addTearDown(fcm.close);
    final resolver = FakeNotificationEventResolver();
    final errors = <Object>[];
    final runtime = NotificationRuntime(
      accounts: FakeNotificationIngressAccountPort(const <String>['work']),
      resolver: resolver,
      dispatch: NotificationDispatchCoordinator(
        notifications: FakeNotificationRepository(),
        delivery: NotificationDeliveryCoordinator(
          privacy: FakeNotificationPrivacyPort(),
          delivery: FakeNotificationDeliveryPort(),
        ),
      ),
      fcm: fcm,
      onError: (_, error, _) => errors.add(error),
    );

    runtime.start();
    fcm.emit(
      _payload(
        id: 'personal-message',
        kind: 'message',
        accountId: 'personal',
        eventId: r'$event',
      ),
    );
    fcm.emitError(StateError('push source unavailable'));
    await runtime.flush();

    expect(resolver.resolutions, isEmpty);
    expect(errors.single, isA<StateError>());
    await runtime.stop();
  });
}

Map<String, String?> _payload({
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
  'event_id': eventId,
  'thread_root_event_id': threadRootEventId,
  'call_id': callId,
};
