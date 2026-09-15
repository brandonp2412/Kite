import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/calls/call_deep_link_coordinator.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  String routingId(String notificationId, {String accountId = 'work'}) =>
      KiteNotification.routingIdFor(
        accountId: accountId,
        notificationId: notificationId,
      );

  group('notification routing', () {
    test(
      'tap activates the owning account and opens exact call destination',
      () async {
        final destination = AppDestination.call(
          accountId: 'work',
          roomId: '!team:example.org',
          callId: 'call-7',
        );
        final notifications = FakeNotificationRepository(<KiteNotification>[
          KiteNotification(
            id: 'notification-1',
            kind: KiteNotificationKind.call,
            destination: destination,
          ),
        ]);
        final accounts = FakeAccountActivationPort('personal');
        final navigation = FakeAppNavigationPort();
        final coordinator = NotificationCoordinator(
          notifications: notifications,
          cancellations: FakeNotificationCancellationPort(),
          accounts: accounts,
          navigation: navigation,
        );

        expect(await coordinator.tap(routingId('notification-1')), isTrue);
        expect(accounts.activeAccountId, 'work');
        expect(accounts.activations, <String>['work']);
        expect(navigation.opened, <AppDestination>[destination]);
      },
    );

    test('tap preserves exact room, event and thread targets without account churn', () async {
      const room = AppDestination.room(
        accountId: 'work',
        roomId: '!invite:example.org',
      );
      final event = AppDestination.event(
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$event',
      );
      final thread = AppDestination.thread(
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$reply',
        threadRootEventId: r'$root',
      );
      final notifications = FakeNotificationRepository(<KiteNotification>[
        const KiteNotification(
          id: 'room',
          kind: KiteNotificationKind.invite,
          destination: room,
        ),
        KiteNotification(
          id: 'event',
          kind: KiteNotificationKind.mention,
          destination: event,
        ),
        KiteNotification(
          id: 'thread',
          kind: KiteNotificationKind.thread,
          destination: thread,
        ),
      ]);
      final accounts = FakeAccountActivationPort('work');
      final navigation = FakeAppNavigationPort();
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        cancellations: FakeNotificationCancellationPort(),
        accounts: accounts,
        navigation: navigation,
      );

      expect(await coordinator.tap(routingId('room')), isTrue);
      expect(await coordinator.tap(routingId('event')), isTrue);
      expect(await coordinator.tap(routingId('thread')), isTrue);
      expect(accounts.activations, isEmpty);
      expect(navigation.opened, <AppDestination>[room, event, thread]);
    });

    test('same source notification id remains isolated per account', () async {
      const workDestination = AppDestination.room(
        accountId: 'work',
        roomId: '!work:example.org',
      );
      const personalDestination = AppDestination.room(
        accountId: 'personal',
        roomId: '!personal:example.org',
      );
      final notifications = FakeNotificationRepository(<KiteNotification>[
        const KiteNotification(
          id: 'shared-id',
          kind: KiteNotificationKind.invite,
          destination: workDestination,
        ),
        const KiteNotification(
          id: 'shared-id',
          kind: KiteNotificationKind.invite,
          destination: personalDestination,
        ),
      ]);
      final accounts = FakeAccountActivationPort('personal');
      final navigation = FakeAppNavigationPort();
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        cancellations: FakeNotificationCancellationPort(),
        accounts: accounts,
        navigation: navigation,
      );

      expect(await coordinator.tap(routingId('shared-id')), isTrue);
      expect(
        await coordinator.tap(routingId('shared-id', accountId: 'personal')),
        isTrue,
      );
      expect(accounts.activations, <String>['work', 'personal']);
      expect(navigation.opened, <AppDestination>[
        workDestination,
        personalDestination,
      ]);
    });

    test('unknown notification is ignored without navigation', () async {
      final notifications = FakeNotificationRepository();
      final accounts = FakeAccountActivationPort('work');
      final navigation = FakeAppNavigationPort();
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        cancellations: FakeNotificationCancellationPort(),
        accounts: accounts,
        navigation: navigation,
      );

      expect(await coordinator.tap('missing'), isFalse);
      expect(accounts.activations, isEmpty);
      expect(navigation.opened, isEmpty);
    });
  });

  group('notification presentation', () {
    test(
      'locked presentation redacts message content but preserves routing',
      () {
        const policy = NotificationPresentationPolicy();
        const notification = KiteNotification(
          id: 'private-message',
          kind: KiteNotificationKind.message,
          destination: AppDestination.event(
            accountId: 'work',
            roomId: '!team:example.org',
            eventId: r'$secret',
          ),
        );

        final presentation = policy.present(
          notification: notification,
          content: const KiteNotificationContent(
            title: 'Alice in Launch room',
            body: 'The recovery key is on my desk',
          ),
          hideContents: true,
        );

        expect(presentation.title, NotificationPresentationPolicy.privateTitle);
        expect(presentation.body, NotificationPresentationPolicy.privateBody);
        expect(presentation.contentsHidden, isTrue);
        expect(presentation.notification, same(notification));
        expect(presentation.notification.destination.eventId, r'$secret');
        expect(presentation.title, isNot(contains('Alice')));
        expect(presentation.body, isNot(contains('recovery key')));
      },
    );

    test('unlocked presentation keeps exact notification content', () {
      const policy = NotificationPresentationPolicy();
      const notification = KiteNotification(
        id: 'visible-message',
        kind: KiteNotificationKind.mention,
        destination: AppDestination.event(
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$mention',
        ),
      );

      final presentation = policy.present(
        notification: notification,
        content: const KiteNotificationContent(
          title: 'Alice',
          body: 'Mentioned you in Launch room',
        ),
        hideContents: false,
      );

      expect(presentation.title, 'Alice');
      expect(presentation.body, 'Mentioned you in Launch room');
      expect(presentation.contentsHidden, isFalse);
    });

    test('call presentation requests incoming-call surface without leaking lock content', () {
      const policy = NotificationPresentationPolicy();
      const notification = KiteNotification(
        id: 'incoming-call',
        kind: KiteNotificationKind.call,
        destination: AppDestination.call(
          accountId: 'work',
          roomId: '!calls:example.org',
          callId: 'matrix-rtc-42',
        ),
      );

      final visible = policy.present(
        notification: notification,
        content: const KiteNotificationContent(
          title: 'Alice',
          body: 'Incoming video call',
        ),
        hideContents: false,
      );
      final locked = policy.present(
        notification: notification,
        content: const KiteNotificationContent(
          title: 'Alice',
          body: 'Incoming video call',
        ),
        hideContents: true,
      );

      expect(visible.surface, KiteNotificationSurface.incomingCall);
      expect(visible.requestsIncomingCallSurface, isTrue);
      expect(visible.title, 'Alice');
      expect(locked.surface, KiteNotificationSurface.incomingCall);
      expect(locked.requestsIncomingCallSurface, isTrue);
      expect(locked.title, NotificationPresentationPolicy.privateTitle);
      expect(locked.body, NotificationPresentationPolicy.privateBody);
      expect(locked.contentsHidden, isTrue);
    });

    test(
      'summaries group by account and room without merging account state',
      () {
        const policy = NotificationPresentationPolicy();
        KiteNotificationPresentation presentation({
          required String id,
          required String accountId,
          required String roomId,
          bool hidden = false,
        }) {
          return policy.present(
            notification: KiteNotification(
              id: id,
              kind: KiteNotificationKind.message,
              destination: AppDestination.event(
                accountId: accountId,
                roomId: roomId,
                eventId: '\$$id',
              ),
            ),
            content: KiteNotificationContent(title: id, body: 'body-$id'),
            hideContents: hidden,
          );
        }

        final summaries = policy.summaries(<KiteNotificationPresentation>[
          presentation(
            id: 'one',
            accountId: 'work',
            roomId: '!team:example.org',
          ),
          presentation(
            id: 'two',
            accountId: 'work',
            roomId: '!team:example.org',
            hidden: true,
          ),
          presentation(
            id: 'personal',
            accountId: 'personal',
            roomId: '!team:example.org',
          ),
          presentation(
            id: 'other-room',
            accountId: 'work',
            roomId: '!other:example.org',
          ),
        ]);

        expect(summaries, hasLength(3));
        final workTeam = summaries.singleWhere(
          (summary) =>
              summary.accountId == 'work' &&
              summary.roomId == '!team:example.org',
        );
        expect(workTeam.count, 2);
        expect(workTeam.contentsHidden, isTrue);
        expect(
          summaries
              .singleWhere((summary) => summary.accountId == 'personal')
              .count,
          1,
        );
        expect(
          () => summaries.add(
            const KiteNotificationSummary(
              groupKey: 'invalid',
              accountId: 'work',
              roomId: '!invalid:example.org',
              count: 1,
              contentsHidden: false,
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );
  });

  group('notification reconciliation', () {
    test(
      'marking a room read clears message, mention and thread only',
      () async {
        AppDestination destination(String accountId, String eventId) =>
            AppDestination.event(
              accountId: accountId,
              roomId: '!team:example.org',
              eventId: eventId,
            );

        final notifications = FakeNotificationRepository(<KiteNotification>[
          KiteNotification(
            id: 'message',
            kind: KiteNotificationKind.message,
            destination: destination('work', r'$message'),
          ),
          KiteNotification(
            id: 'mention',
            kind: KiteNotificationKind.mention,
            destination: destination('work', r'$mention'),
          ),
          KiteNotification(
            id: 'thread',
            kind: KiteNotificationKind.thread,
            destination: AppDestination.thread(
              accountId: 'work',
              roomId: '!team:example.org',
              eventId: r'$reply',
              threadRootEventId: r'$root',
            ),
          ),
          KiteNotification(
            id: 'invite',
            kind: KiteNotificationKind.invite,
            destination: const AppDestination.room(
              accountId: 'work',
              roomId: '!team:example.org',
            ),
          ),
          KiteNotification(
            id: 'call',
            kind: KiteNotificationKind.call,
            destination: const AppDestination.call(
              accountId: 'work',
              roomId: '!team:example.org',
              callId: 'call-1',
            ),
          ),
          KiteNotification(
            id: 'other-account',
            kind: KiteNotificationKind.message,
            destination: destination('personal', r'$personal'),
          ),
        ]);
        final cancellations = FakeNotificationCancellationPort();
        final coordinator = NotificationCoordinator(
          notifications: notifications,
          cancellations: cancellations,
          accounts: FakeAccountActivationPort('work'),
          navigation: FakeAppNavigationPort(),
        );

        expect(
          await coordinator.markRoomRead(
            accountId: 'work',
            roomId: '!team:example.org',
          ),
          3,
        );
        expect(cancellations.cancelledIds, <String>[
          routingId('message'),
          routingId('mention'),
          routingId('thread'),
        ]);
        expect(notifications.removedIds, <String>[
          routingId('message'),
          routingId('mention'),
          routingId('thread'),
        ]);
        expect(notifications.notification(routingId('invite')), isNotNull);
        expect(notifications.notification(routingId('call')), isNotNull);
        expect(
          notifications.notification(
            routingId('other-account', accountId: 'personal'),
          ),
          isNotNull,
        );
      },
    );

    test(
      'remote read reconciliation removes only matching event notifications',
      () async {
        final notifications = FakeNotificationRepository(<KiteNotification>[
          KiteNotification(
            id: 'read',
            kind: KiteNotificationKind.message,
            destination: const AppDestination.event(
              accountId: 'work',
              roomId: '!one:example.org',
              eventId: r'$read',
            ),
          ),
          KiteNotification(
            id: 'unread',
            kind: KiteNotificationKind.message,
            destination: const AppDestination.event(
              accountId: 'work',
              roomId: '!one:example.org',
              eventId: r'$unread',
            ),
          ),
          KiteNotification(
            id: 'other-account',
            kind: KiteNotificationKind.message,
            destination: const AppDestination.event(
              accountId: 'personal',
              roomId: '!one:example.org',
              eventId: r'$read',
            ),
          ),
        ]);
        final cancellations = FakeNotificationCancellationPort();
        final coordinator = NotificationCoordinator(
          notifications: notifications,
          cancellations: cancellations,
          accounts: FakeAccountActivationPort('work'),
          navigation: FakeAppNavigationPort(),
        );

        expect(
          await coordinator.reconcileReadEvents(
            accountId: 'work',
            eventIds: const <String>[r'$read'],
          ),
          1,
        );
        expect(cancellations.cancelledIds, <String>[routingId('read')]);
        expect(notifications.notification(routingId('read')), isNull);
        expect(notifications.notification(routingId('unread')), isNotNull);
        expect(
          notifications.notification(
            routingId('other-account', accountId: 'personal'),
          ),
          isNotNull,
        );
      },
    );
  });

  test(
    'call deep-link coordinator activates account and preserves call identity',
    () async {
      final accounts = FakeAccountActivationPort('personal');
      final navigation = FakeAppNavigationPort();
      final coordinator = CallDeepLinkCoordinator(
        accounts: accounts,
        navigation: navigation,
      );
      const target = CallDeepLinkTarget(
        accountId: 'work',
        roomId: '!team:example.org',
        callId: 'matrix-rtc-session',
      );

      await coordinator.open(target);

      expect(accounts.activations, <String>['work']);
      expect(navigation.opened, <AppDestination>[
        const AppDestination.call(
          accountId: 'work',
          roomId: '!team:example.org',
          callId: 'matrix-rtc-session',
        ),
      ]);
    },
  );

  test('call deep-link coordinator rejects malformed identity before account switch', () async {
    final accounts = FakeAccountActivationPort('personal');
    final navigation = FakeAppNavigationPort();
    final coordinator = CallDeepLinkCoordinator(
      accounts: accounts,
      navigation: navigation,
    );

    await expectLater(
      coordinator.open(
        const CallDeepLinkTarget(
          accountId: 'work',
          roomId: 'team:example.org',
          callId: 'matrix-rtc-session',
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      coordinator.open(
        const CallDeepLinkTarget(
          accountId: 'work',
          roomId: '!team:example.org',
          callId: 'call with spaces',
        ),
      ),
      throwsArgumentError,
    );

    expect(accounts.activeAccountId, 'personal');
    expect(accounts.activations, isEmpty);
    expect(navigation.opened, isEmpty);
  });
}
