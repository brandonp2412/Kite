import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_resolution.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  test(
    'validated push identity resolves SDK content before platform delivery',
    () async {
      final fixture = _fixture();
      fixture.resolver.event = const MatrixNotificationEvent(
        id: 'push-1',
        kind: MatrixNotificationEventKind.message,
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$event',
        title: 'Alice',
        body: 'Decrypted Matrix message',
      );
      final ingress = _messageIngress();

      final result = await fixture.resolution.resolveAndDispatch(ingress);

      expect(result.status, NotificationResolutionStatus.delivered);
      expect(fixture.resolver.resolutions, hasLength(1));
      expect(fixture.platform.shown.single.title, 'Alice');
      expect(fixture.platform.shown.single.body, 'Decrypted Matrix message');
      expect(
        fixture.repository.notification(ingress.notification!.routingId),
        isNotNull,
      );
    },
  );

  test('stale SDK state safely drops a validated push', () async {
    final fixture = _fixture();

    final result = await fixture.resolution.resolveAndDispatch(
      _messageIngress(),
    );

    expect(result.status, NotificationResolutionStatus.stale);
    expect(fixture.platform.shown, isEmpty);
    expect(fixture.repository.activeForAccount('work'), isEmpty);
  });

  test('SDK resolution cannot substitute another Matrix target', () async {
    final fixture = _fixture();
    fixture.resolver.event = const MatrixNotificationEvent(
      id: 'push-1',
      kind: MatrixNotificationEventKind.message,
      accountId: 'work',
      roomId: '!other:example.org',
      eventId: r'$event',
      title: 'Mallory',
      body: 'Wrong room',
    );

    await expectLater(
      fixture.resolution.resolveAndDispatch(_messageIngress()),
      throwsStateError,
    );

    expect(fixture.platform.shown, isEmpty);
    expect(fixture.repository.activeForAccount('work'), isEmpty);
  });

  test('accepted ingress can bind directly to secure SDK resolution', () async {
    final fixture = _fixture();
    fixture.resolver.event = const MatrixNotificationEvent(
      id: 'push-call',
      kind: MatrixNotificationEventKind.call,
      accountId: 'work',
      roomId: '!calls:example.org',
      callId: 'rtc-42',
      title: 'Alice',
      body: 'Incoming video call',
    );
    final ingress = NotificationIngressCoordinator(
      accounts: FakeNotificationIngressAccountPort(const <String>['work']),
      onAccepted: fixture.resolution.handleAccepted,
    );

    final result = await ingress.receive(
      transport: NotificationIngressTransport.backgroundSync,
      data: const <String, String?>{
        'notification_id': 'push-call',
        'kind': 'call',
        'account_id': 'work',
        'room_id': '!calls:example.org',
        'call_id': 'rtc-42',
      },
    );

    expect(result.accepted, isTrue);
    expect(fixture.platform.shown.single.requestsIncomingCallSurface, isTrue);
    expect(fixture.platform.shown.single.body, 'Incoming video call');
  });

  test(
    'dispatch policy suppression remains distinct from stale resolution',
    () async {
      final fixture = _fixture(
        policy: FakeNotificationDispatchPolicy()..allow = false,
      );
      fixture.resolver.event = const MatrixNotificationEvent(
        id: 'push-1',
        kind: MatrixNotificationEventKind.message,
        accountId: 'work',
        roomId: '!team:example.org',
        eventId: r'$event',
        title: 'Alice',
        body: 'Muted',
      );

      final result = await fixture.resolution.resolveAndDispatch(
        _messageIngress(),
      );

      expect(result.status, NotificationResolutionStatus.suppressed);
      expect(fixture.platform.shown, isEmpty);
      expect(fixture.repository.activeForAccount('work'), isEmpty);
    },
  );

  test('rejected ingress is never eligible for SDK resolution', () async {
    final fixture = _fixture();
    final rejected = const NotificationIngressParser().parse(
      transport: NotificationIngressTransport.fcm,
      data: const <String, String?>{
        'notification_id': 'bad',
        'kind': 'message',
        'account_id': 'work',
        'room_id': '!team:example.org',
      },
    );

    await expectLater(
      fixture.resolution.resolveAndDispatch(rejected),
      throwsStateError,
    );
    expect(fixture.resolver.resolutions, isEmpty);
  });
}

NotificationIngressResult _messageIngress() =>
    const NotificationIngressParser().parse(
      transport: NotificationIngressTransport.fcm,
      data: const <String, String?>{
        'notification_id': 'push-1',
        'kind': 'message',
        'account_id': 'work',
        'room_id': '!team:example.org',
        'event_id': r'$event',
      },
    );

_ResolutionFixture _fixture({NotificationDispatchPolicyPort? policy}) {
  final resolver = FakeNotificationEventResolver();
  final repository = FakeNotificationRepository();
  final platform = FakeNotificationDeliveryPort();
  final dispatch = NotificationDispatchCoordinator(
    notifications: repository,
    delivery: NotificationDeliveryCoordinator(
      privacy: FakeNotificationPrivacyPort(),
      delivery: platform,
    ),
    policy: policy ?? const AllowAllNotificationDispatchPolicy(),
  );
  return _ResolutionFixture(
    resolver: resolver,
    repository: repository,
    platform: platform,
    resolution: NotificationResolutionCoordinator(
      resolver: resolver,
      dispatch: dispatch,
    ),
  );
}

final class _ResolutionFixture {
  const _ResolutionFixture({
    required this.resolver,
    required this.repository,
    required this.platform,
    required this.resolution,
  });

  final FakeNotificationEventResolver resolver;
  final FakeNotificationRepository repository;
  final FakeNotificationDeliveryPort platform;
  final NotificationResolutionCoordinator resolution;
}
