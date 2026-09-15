import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/notification_settings_policy.dart';
import 'package:kite/features/settings/settings_controller.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  test('master notification setting suppresses every dispatch kind', () {
    final source = FakeNotificationPreferencesSource(
      const NotificationPreferences(
        masterEnabled: false,
        enabledCategories: <NotificationCategory>{
          NotificationCategory.messages,
          NotificationCategory.mentions,
          NotificationCategory.calls,
        },
      ),
    );
    final policy = SettingsNotificationDispatchPolicy(source);

    for (final event in _events()) {
      expect(
        policy.allows(event: event, notification: _notificationFor(event)),
        isFalse,
        reason: event.kind.name,
      );
    }
  });

  test(
    'account categories route message, mention, thread and call independently',
    () {
      final source = FakeNotificationPreferencesSource(
        const NotificationPreferences(
          masterEnabled: true,
          enabledCategories: <NotificationCategory>{
            NotificationCategory.mentions,
          },
        ),
      );
      final policy = SettingsNotificationDispatchPolicy(source);
      final events = _events();

      expect(
        _allows(policy, events, MatrixNotificationEventKind.message),
        isFalse,
      );
      expect(
        _allows(policy, events, MatrixNotificationEventKind.thread),
        isFalse,
      );
      expect(
        _allows(policy, events, MatrixNotificationEventKind.mention),
        isTrue,
      );
      expect(
        _allows(policy, events, MatrixNotificationEventKind.call),
        isFalse,
      );
      expect(
        _allows(policy, events, MatrixNotificationEventKind.invite),
        isTrue,
      );
    },
  );

  test(
    'per-room modes override account defaults only for room message events',
    () {
      final source = FakeNotificationPreferencesSource(
        const NotificationPreferences(
          masterEnabled: true,
          enabledCategories: <NotificationCategory>{NotificationCategory.calls},
          roomModes: <String, RoomNotificationMode>{
            '!all:example.org': RoomNotificationMode.allMessages,
            '!mentions:example.org': RoomNotificationMode.mentionsOnly,
            '!muted:example.org': RoomNotificationMode.mute,
          },
        ),
      );
      final policy = SettingsNotificationDispatchPolicy(source);

      expect(
        policy.allows(
          event: _message('!all:example.org'),
          notification: _messageNotification('!all:example.org'),
        ),
        isTrue,
      );
      expect(
        policy.allows(
          event: _mention('!all:example.org'),
          notification: _mentionNotification('!all:example.org'),
        ),
        isTrue,
      );
      expect(
        policy.allows(
          event: _message('!mentions:example.org'),
          notification: _messageNotification('!mentions:example.org'),
        ),
        isFalse,
      );
      expect(
        policy.allows(
          event: _mention('!mentions:example.org'),
          notification: _mentionNotification('!mentions:example.org'),
        ),
        isTrue,
      );
      expect(
        policy.allows(
          event: _message('!muted:example.org'),
          notification: _messageNotification('!muted:example.org'),
        ),
        isFalse,
      );

      final call = _call('!muted:example.org');
      expect(
        policy.allows(event: call, notification: _notificationFor(call)),
        isTrue,
      );
    },
  );

  test('dispatcher consults live settings before platform delivery', () async {
    final source = FakeNotificationPreferencesSource();
    final repository = FakeNotificationRepository();
    final platform = FakeNotificationDeliveryPort();
    final dispatcher = NotificationDispatchCoordinator(
      notifications: repository,
      delivery: NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: platform,
      ),
      policy: SettingsNotificationDispatchPolicy(source),
    );
    final event = _message('!team:example.org');

    expect(await dispatcher.dispatch(event), isNotNull);
    expect(platform.shown, hasLength(1));

    source.notificationPreferences = const NotificationPreferences(
      masterEnabled: false,
      enabledCategories: <NotificationCategory>{
        NotificationCategory.messages,
        NotificationCategory.mentions,
        NotificationCategory.calls,
      },
    );
    final suppressed = _message('!other:example.org', id: 'suppressed');

    expect(await dispatcher.dispatch(suppressed), isNull);
    expect(platform.shown, hasLength(1));
    expect(
      repository.notification(
        KiteNotification.routingIdFor(
          accountId: 'work',
          notificationId: 'suppressed',
        ),
      ),
      isNull,
    );
  });
}

bool _allows(
  SettingsNotificationDispatchPolicy policy,
  List<MatrixNotificationEvent> events,
  MatrixNotificationEventKind kind,
) {
  final event = events.singleWhere((entry) => entry.kind == kind);
  return policy.allows(event: event, notification: _notificationFor(event));
}

List<MatrixNotificationEvent> _events() => <MatrixNotificationEvent>[
  _message('!team:example.org'),
  _mention('!team:example.org'),
  const MatrixNotificationEvent(
    id: 'thread',
    kind: MatrixNotificationEventKind.thread,
    accountId: 'work',
    roomId: '!team:example.org',
    eventId: r'$reply',
    threadRootEventId: r'$root',
    title: 'Thread',
    body: 'Reply',
  ),
  const MatrixNotificationEvent(
    id: 'invite',
    kind: MatrixNotificationEventKind.invite,
    accountId: 'work',
    roomId: '!invite:example.org',
    title: 'Invite',
    body: 'Invited',
  ),
  _call('!team:example.org'),
];

MatrixNotificationEvent _message(String roomId, {String id = 'message'}) =>
    MatrixNotificationEvent(
      id: id,
      kind: MatrixNotificationEventKind.message,
      accountId: 'work',
      roomId: roomId,
      eventId: '\$$id',
      title: 'Alice',
      body: 'Message',
    );

MatrixNotificationEvent _mention(String roomId) => MatrixNotificationEvent(
  id: 'mention',
  kind: MatrixNotificationEventKind.mention,
  accountId: 'work',
  roomId: roomId,
  eventId: r'$mention',
  title: 'Alice',
  body: 'Mention',
);

MatrixNotificationEvent _call(String roomId) => MatrixNotificationEvent(
  id: 'call',
  kind: MatrixNotificationEventKind.call,
  accountId: 'work',
  roomId: roomId,
  callId: 'rtc-42',
  title: 'Call',
  body: 'Incoming call',
);

KiteNotification _messageNotification(String roomId) => KiteNotification(
  id: 'message',
  kind: KiteNotificationKind.message,
  destination: AppDestination.event(
    accountId: 'work',
    roomId: roomId,
    eventId: r'$message',
  ),
);

KiteNotification _mentionNotification(String roomId) => KiteNotification(
  id: 'mention',
  kind: KiteNotificationKind.mention,
  destination: AppDestination.event(
    accountId: 'work',
    roomId: roomId,
    eventId: r'$mention',
  ),
);

KiteNotification _notificationFor(MatrixNotificationEvent event) {
  final destination = switch (event.kind) {
    MatrixNotificationEventKind.message ||
    MatrixNotificationEventKind.mention => AppDestination.event(
      accountId: event.accountId,
      roomId: event.roomId,
      eventId: event.eventId!,
    ),
    MatrixNotificationEventKind.invite => AppDestination.room(
      accountId: event.accountId,
      roomId: event.roomId,
    ),
    MatrixNotificationEventKind.thread => AppDestination.thread(
      accountId: event.accountId,
      roomId: event.roomId,
      eventId: event.eventId!,
      threadRootEventId: event.threadRootEventId!,
    ),
    MatrixNotificationEventKind.call => AppDestination.call(
      accountId: event.accountId,
      roomId: event.roomId,
      callId: event.callId!,
    ),
  };
  final kind = switch (event.kind) {
    MatrixNotificationEventKind.message => KiteNotificationKind.message,
    MatrixNotificationEventKind.mention => KiteNotificationKind.mention,
    MatrixNotificationEventKind.invite => KiteNotificationKind.invite,
    MatrixNotificationEventKind.thread => KiteNotificationKind.thread,
    MatrixNotificationEventKind.call => KiteNotificationKind.call,
  };
  return KiteNotification(id: event.id, kind: kind, destination: destination);
}
