import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  const parser = NotificationIngressParser();

  Map<String, String?> base(String kind) => <String, String?>{
    'notification_id': 'push-1',
    'kind': kind,
    'account_id': 'work',
    'room_id': '!team:example.org',
  };

  test(
    'FCM and background sync produce the same account-aware event target',
    () {
      final payload = base('mention')..['event_id'] = r'$mention';

      final fcm = parser.parse(
        transport: NotificationIngressTransport.fcm,
        data: payload,
      );
      final background = parser.parse(
        transport: NotificationIngressTransport.backgroundSync,
        data: payload,
      );

      expect(fcm.accepted, isTrue);
      expect(background.accepted, isTrue);
      expect(fcm.transport, NotificationIngressTransport.fcm);
      expect(background.transport, NotificationIngressTransport.backgroundSync);
      expect(fcm.notification?.kind, KiteNotificationKind.mention);
      expect(
        fcm.notification?.destination,
        background.notification?.destination,
      );
      expect(
        fcm.notification?.destination,
        const AppDestination.event(
          accountId: 'work',
          roomId: '!team:example.org',
          eventId: r'$mention',
        ),
      );
    },
  );

  test('all notification kinds preserve exact destination identity', () {
    final message = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('message')..['event_id'] = r'$message',
    );
    final invite = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('invite'),
    );
    final thread = parser.parse(
      transport: NotificationIngressTransport.backgroundSync,
      data: base('thread')
        ..['event_id'] = r'$reply'
        ..['thread_root_event_id'] = r'$root',
    );
    final call = parser.parse(
      transport: NotificationIngressTransport.backgroundSync,
      data: base('call')..['call_id'] = 'matrix-rtc-session',
    );

    expect(
      message.notification?.destination,
      const AppDestination.event(
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$message',
      ),
    );
    expect(
      invite.notification?.destination,
      const AppDestination.room(accountId: 'work', roomId: '!team:example.org'),
    );
    expect(
      thread.notification?.destination,
      const AppDestination.thread(
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$reply',
        threadRootEventId: r'$root',
      ),
    );
    expect(
      call.notification?.destination,
      const AppDestination.call(
        accountId: 'work',
        roomId: '!team:example.org',
        callId: 'matrix-rtc-session',
      ),
    );
  });

  test(
    'parser trims transport metadata but never rewrites target identity',
    () {
      final result = parser.parse(
        transport: NotificationIngressTransport.fcm,
        data: <String, String?>{
          'notification_id': ' push-1 ',
          'kind': ' message ',
          'account_id': ' work ',
          'room_id': ' !room:example.org ',
          'event_id': r' $event ',
        },
      );

      expect(result.accepted, isTrue);
      expect(result.notification?.id, 'push-1');
      expect(
        result.notification?.destination,
        const AppDestination.event(
          accountId: 'work',
          roomId: '!room:example.org',
          eventId: r'$event',
        ),
      );
    },
  );

  test('missing required routing metadata is rejected deterministically', () {
    NotificationIngressFailure? failureFor(Map<String, String?> payload) =>
        parser
            .parse(
              transport: NotificationIngressTransport.backgroundSync,
              data: payload,
            )
            .failure;

    expect(
      failureFor(<String, String?>{'kind': 'invite'}),
      NotificationIngressFailure.missingNotificationId,
    );
    expect(
      failureFor(<String, String?>{'notification_id': 'id'}),
      NotificationIngressFailure.missingKind,
    );
    expect(
      failureFor(<String, String?>{
        'notification_id': 'id',
        'kind': 'reaction',
      }),
      NotificationIngressFailure.unsupportedKind,
    );
    expect(
      failureFor(<String, String?>{'notification_id': 'id', 'kind': 'invite'}),
      NotificationIngressFailure.missingAccountId,
    );
    expect(
      failureFor(<String, String?>{
        'notification_id': 'id',
        'kind': 'invite',
        'account_id': 'work',
      }),
      NotificationIngressFailure.missingRoomId,
    );
    expect(
      failureFor(base('message')),
      NotificationIngressFailure.missingEventId,
    );
    expect(
      failureFor(base('thread')..['event_id'] = r'$reply'),
      NotificationIngressFailure.missingThreadRootEventId,
    );
    expect(failureFor(base('call')), NotificationIngressFailure.missingCallId);
  });

  test('malformed Matrix target identities are rejected before routing', () {
    final invalidRoom = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('invite')..['room_id'] = 'room:example.org',
    );
    final invalidEvent = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('message')..['event_id'] = 'event',
    );
    final invalidRoot = parser.parse(
      transport: NotificationIngressTransport.backgroundSync,
      data: base('thread')
        ..['event_id'] = r'$reply'
        ..['thread_root_event_id'] = 'root',
    );
    final invalidCall = parser.parse(
      transport: NotificationIngressTransport.backgroundSync,
      data: base('call')..['call_id'] = 'call with spaces',
    );

    expect(invalidRoom.failure, NotificationIngressFailure.invalidRoomId);
    expect(invalidEvent.failure, NotificationIngressFailure.invalidEventId);
    expect(
      invalidRoot.failure,
      NotificationIngressFailure.invalidThreadRootEventId,
    );
    expect(invalidCall.failure, NotificationIngressFailure.invalidCallId);
  });

  test('cross-kind target fields are rejected instead of misrouting', () {
    final invite = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('invite')..['event_id'] = r'$wrong',
    );
    final message = parser.parse(
      transport: NotificationIngressTransport.fcm,
      data: base('message')
        ..['event_id'] = r'$event'
        ..['call_id'] = 'wrong-call',
    );
    final call = parser.parse(
      transport: NotificationIngressTransport.backgroundSync,
      data: base('call')
        ..['call_id'] = 'call-1'
        ..['thread_root_event_id'] = r'$wrong-root',
    );

    expect(invite.failure, NotificationIngressFailure.unexpectedTargetField);
    expect(message.failure, NotificationIngressFailure.unexpectedTargetField);
    expect(call.failure, NotificationIngressFailure.unexpectedTargetField);
  });

  test(
    'coordinator forwards only accepted transport-neutral notifications',
    () async {
      final accepted = <NotificationIngressResult>[];
      final accounts = FakeNotificationIngressAccountPort(<String>['work']);
      final coordinator = NotificationIngressCoordinator(
        accounts: accounts,
        onAccepted: (result) async => accepted.add(result),
      );

      final good = await coordinator.receive(
        transport: NotificationIngressTransport.fcm,
        data: base('call')..['call_id'] = 'call-1',
      );
      final bad = await coordinator.receive(
        transport: NotificationIngressTransport.backgroundSync,
        data: base('thread'),
      );
      final unknownAccount = await coordinator.receive(
        transport: NotificationIngressTransport.fcm,
        data: base('call')
          ..['account_id'] = 'signed-out'
          ..['call_id'] = 'call-2',
      );

      expect(good.accepted, isTrue);
      expect(bad.accepted, isFalse);
      expect(unknownAccount.accepted, isFalse);
      expect(unknownAccount.failure, NotificationIngressFailure.unknownAccount);
      expect(accepted, <NotificationIngressResult>[good]);
      expect(accepted.single.notification?.destination.accountId, 'work');
      expect(accounts.queries, <String>['work', 'signed-out']);
    },
  );
}
