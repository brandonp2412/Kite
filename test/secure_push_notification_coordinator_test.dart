import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/push_registration.dart';
import 'package:kite/features/notifications/secure_push_notification_coordinator.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

final class _PushGateway implements PushRegistrationGateway {
  DecryptedPushNotification? decoded;

  @override
  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) async => decoded;

  @override
  Future<void> register({
    required String accountId,
    required PushProvider provider,
    required String deviceToken,
  }) async {}

  @override
  Future<void> unregister({required String accountId}) async {}
}

final class _BadgeRefresh implements NotificationBadgeRefreshPort {
  int refreshes = 0;
  Object? failure;

  @override
  Future<void> refreshBadgeCount() async {
    refreshes += 1;
    if (failure case final error?) throw error;
  }
}

DecryptedPushNotification _decoded({
  String id = 'push-1',
  String accountId = 'work',
  String roomId = '!room:example.org',
  String eventId = r'$event',
  KiteNotificationKind kind = KiteNotificationKind.message,
  String body = 'Sensitive message',
}) {
  return DecryptedPushNotification(
    notification: KiteNotification(
      id: id,
      kind: kind,
      destination: AppDestination.event(
        accountId: accountId,
        roomId: roomId,
        eventId: eventId,
      ),
    ),
    content: KiteNotificationContent(title: 'Alice', body: body),
  );
}

void main() {
  test(
    'secure ingress routes decoded payload through privacy and badge state',
    () async {
      final pushGateway = _PushGateway()..decoded = _decoded();
      final push = PushRegistrationController(pushGateway);
      addTearDown(push.dispose);
      final repository = FakeNotificationRepository();
      final deliveryPort = FakeNotificationDeliveryPort();
      final delivery = NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(hideNotificationContents: true),
        delivery: deliveryPort,
      );
      final badges = _BadgeRefresh();
      final coordinator = SecurePushNotificationCoordinator(
        pushRegistration: push,
        notifications: repository,
        delivery: delivery,
        badgeRefresh: badges,
      );

      expect(
        await coordinator.handleEncryptedPayload(
          accountId: 'work',
          encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
        ),
        isTrue,
      );
      expect(repository.notification('push-1'), isNotNull);
      expect(deliveryPort.shown, hasLength(1));
      expect(deliveryPort.shown.single.contentsHidden, isTrue);
      expect(
        deliveryPort.shown.single.body,
        NotificationPresentationPolicy.privateBody,
      );
      expect(badges.refreshes, 1);
    },
  );

  test('decoded payload cannot cross account boundaries', () async {
    final pushGateway = _PushGateway()
      ..decoded = _decoded(accountId: 'personal');
    final push = PushRegistrationController(pushGateway);
    addTearDown(push.dispose);
    final repository = FakeNotificationRepository();
    final deliveryPort = FakeNotificationDeliveryPort();
    final badges = _BadgeRefresh();
    final coordinator = SecurePushNotificationCoordinator(
      pushRegistration: push,
      notifications: repository,
      delivery: NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: deliveryPort,
      ),
      badgeRefresh: badges,
    );

    expect(
      await coordinator.handleEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
      ),
      isFalse,
    );
    expect(repository.activeForAccount('personal'), isEmpty);
    expect(deliveryPort.shown, isEmpty);
    expect(badges.refreshes, 0);
    expect(push.errorMessage.value, 'Kite received an invalid notification.');
  });

  test('malformed decoded Matrix destinations never reach delivery', () async {
    final pushGateway = _PushGateway()
      ..decoded = _decoded(roomId: 'room-without-sigil');
    final push = PushRegistrationController(pushGateway);
    addTearDown(push.dispose);
    final repository = FakeNotificationRepository();
    final deliveryPort = FakeNotificationDeliveryPort();
    final badges = _BadgeRefresh();
    final coordinator = SecurePushNotificationCoordinator(
      pushRegistration: push,
      notifications: repository,
      delivery: NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: deliveryPort,
      ),
      badgeRefresh: badges,
    );

    expect(
      await coordinator.handleEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
      ),
      isFalse,
    );
    expect(repository.activeForAccount('work'), isEmpty);
    expect(deliveryPort.shown, isEmpty);
    expect(badges.refreshes, 0);

    pushGateway.decoded = _decoded(eventId: 'event-without-sigil');
    expect(
      await coordinator.handleEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
      ),
      isFalse,
    );
    expect(deliveryPort.shown, isEmpty);

    pushGateway.decoded = _decoded(kind: KiteNotificationKind.call);
    expect(
      await coordinator.handleEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
      ),
      isFalse,
    );
    expect(deliveryPort.shown, isEmpty);
  });

  test('delivery failure restores previous routing metadata', () async {
    final previous = _decoded(body: 'Old body').notification;
    final pushGateway = _PushGateway()..decoded = _decoded(body: 'New body');
    final push = PushRegistrationController(pushGateway);
    addTearDown(push.dispose);
    final repository = FakeNotificationRepository(<KiteNotification>[previous]);
    final deliveryPort = FakeNotificationDeliveryPort()
      ..failNextWith = StateError('platform delivery failed');
    final badges = _BadgeRefresh();
    final coordinator = SecurePushNotificationCoordinator(
      pushRegistration: push,
      notifications: repository,
      delivery: NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: deliveryPort,
      ),
      badgeRefresh: badges,
    );

    expect(
      await coordinator.handleEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
      ),
      isFalse,
    );
    expect(repository.notification('push-1'), same(previous));
    expect(badges.refreshes, 0);
  });

  test(
    'badge failure does not discard an already delivered notification',
    () async {
      final pushGateway = _PushGateway()..decoded = _decoded();
      final push = PushRegistrationController(pushGateway);
      addTearDown(push.dispose);
      final repository = FakeNotificationRepository();
      final deliveryPort = FakeNotificationDeliveryPort();
      final badges = _BadgeRefresh()..failure = StateError('badge unavailable');
      final coordinator = SecurePushNotificationCoordinator(
        pushRegistration: push,
        notifications: repository,
        delivery: NotificationDeliveryCoordinator(
          privacy: FakeNotificationPrivacyPort(),
          delivery: deliveryPort,
        ),
        badgeRefresh: badges,
      );

      expect(
        await coordinator.handleEncryptedPayload(
          accountId: 'work',
          encryptedPayload: 'OPAQUE-ENCRYPTED-PAYLOAD',
        ),
        isTrue,
      );
      expect(repository.notification('push-1'), isNotNull);
      expect(deliveryPort.shown, hasLength(1));
      expect(badges.refreshes, 1);
    },
  );
}
