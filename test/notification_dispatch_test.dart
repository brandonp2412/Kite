import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  test(
    'dispatch maps message, mention, invite, thread, and call to exact targets',
    () async {
      final repository = FakeNotificationRepository();
      final platform = FakeNotificationDeliveryPort();
      final dispatcher = NotificationDispatchCoordinator(
        notifications: repository,
        delivery: NotificationDeliveryCoordinator(
          privacy: FakeNotificationPrivacyPort(),
          delivery: platform,
        ),
      );

      final events = <MatrixNotificationEvent>[
        const MatrixNotificationEvent(
          id: 'message',
          kind: MatrixNotificationEventKind.message,
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$message',
          title: 'Alice',
          body: 'Message body',
        ),
        const MatrixNotificationEvent(
          id: 'mention',
          kind: MatrixNotificationEventKind.mention,
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$mention',
          title: 'Bob',
          body: 'Mentioned you',
        ),
        const MatrixNotificationEvent(
          id: 'invite',
          kind: MatrixNotificationEventKind.invite,
          accountId: 'work',
          roomId: '!invite:example.org',
          title: 'Room invite',
          body: 'Invited by Carol',
        ),
        const MatrixNotificationEvent(
          id: 'thread',
          kind: MatrixNotificationEventKind.thread,
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$reply',
          threadRootEventId: r'$root',
          title: 'Thread reply',
          body: 'Dave replied',
        ),
        const MatrixNotificationEvent(
          id: 'call',
          kind: MatrixNotificationEventKind.call,
          accountId: 'personal',
          roomId: '!calls:example.org',
          callId: 'matrix-rtc-42',
          title: 'Incoming call',
          body: 'Erin is calling',
        ),
      ];

      for (final event in events) {
        await dispatcher.dispatch(event);
      }

      expect(
        repository.notification('message')!.destination,
        const AppDestination.event(
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$message',
        ),
      );
      expect(
        repository.notification('mention')!.kind,
        KiteNotificationKind.mention,
      );
      expect(
        repository.notification('invite')!.destination,
        const AppDestination.room(
          accountId: 'work',
          roomId: '!invite:example.org',
        ),
      );
      expect(
        repository.notification('thread')!.destination,
        const AppDestination.thread(
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$reply',
          threadRootEventId: r'$root',
        ),
      );
      expect(
        repository.notification('call')!.destination,
        const AppDestination.call(
          accountId: 'personal',
          roomId: '!calls:example.org',
          callId: 'matrix-rtc-42',
        ),
      );
      expect(
        platform.shown.map((item) => item.notification.kind),
        <KiteNotificationKind>[
          KiteNotificationKind.message,
          KiteNotificationKind.mention,
          KiteNotificationKind.invite,
          KiteNotificationKind.thread,
          KiteNotificationKind.call,
        ],
      );
      expect(platform.shown.map((item) => item.body), <String>[
        'Message body',
        'Mentioned you',
        'Invited by Carol',
        'Dave replied',
        'Erin is calling',
      ]);
    },
  );

  test('invalid event identity and failed platform delivery never register routing', () async {
    final repository = FakeNotificationRepository();
    final platform = FakeNotificationDeliveryPort();
    final dispatcher = NotificationDispatchCoordinator(
      notifications: repository,
      delivery: NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: platform,
      ),
    );

    await expectLater(
      dispatcher.dispatch(
        const MatrixNotificationEvent(
          id: 'bad-thread',
          kind: MatrixNotificationEventKind.thread,
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$reply',
          title: 'Thread',
          body: 'Missing root',
        ),
      ),
      throwsArgumentError,
    );
    expect(repository.notification('bad-thread'), isNull);

    await expectLater(
      dispatcher.dispatch(
        const MatrixNotificationEvent(
          id: 'bad-call',
          kind: MatrixNotificationEventKind.call,
          accountId: 'work',
          roomId: '!calls:example.org',
          title: 'Incoming call',
          body: 'Missing MatrixRTC identity',
        ),
      ),
      throwsArgumentError,
    );
    expect(repository.notification('bad-call'), isNull);

    for (final invalid in <MatrixNotificationEvent>[
      const MatrixNotificationEvent(
        id: 'bad-room',
        kind: MatrixNotificationEventKind.invite,
        accountId: 'work',
        roomId: 'room:example.org',
        title: 'Invite',
        body: 'Malformed room id',
      ),
      const MatrixNotificationEvent(
        id: 'bad-event',
        kind: MatrixNotificationEventKind.message,
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: 'event',
        title: 'Message',
        body: 'Malformed event id',
      ),
      const MatrixNotificationEvent(
        id: 'cross-kind',
        kind: MatrixNotificationEventKind.call,
        accountId: 'work',
        roomId: '!calls:example.org',
        eventId: r'$wrong',
        callId: 'rtc-42',
        title: 'Call',
        body: 'Conflicting target identity',
      ),
    ]) {
      await expectLater(dispatcher.dispatch(invalid), throwsArgumentError);
      expect(repository.notification(invalid.id), isNull);
    }
    expect(platform.shown, isEmpty);

    platform.failNextWith = StateError('platform unavailable');
    await expectLater(
      dispatcher.dispatch(
        const MatrixNotificationEvent(
          id: 'failed',
          kind: MatrixNotificationEventKind.message,
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$failed',
          title: 'Alice',
          body: 'Body',
        ),
      ),
      throwsStateError,
    );
    expect(repository.notification('failed'), isNull);
  });
}
