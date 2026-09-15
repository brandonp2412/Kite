import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  KiteNotification notification({
    required String id,
    String accountId = 'work',
    String roomId = '!team:example.org',
  }) {
    return KiteNotification(
      id: id,
      kind: KiteNotificationKind.message,
      destination: AppDestination.event(
        accountId: accountId,
        roomId: roomId,
        eventId: '\$$id',
      ),
    );
  }

  KiteNotificationContent content(String id) =>
      KiteNotificationContent(title: 'Sender $id', body: 'Message $id');

  test(
    'delivery groups multiple notifications from the same account room',
    () async {
      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: delivery,
      );

      await coordinator.upsert(
        notification: notification(id: 'one'),
        content: content('one'),
      );
      expect(delivery.summaries, isEmpty);

      await coordinator.upsert(
        notification: notification(id: 'two'),
        content: content('two'),
      );

      expect(delivery.shown, hasLength(2));
      expect(delivery.summaries, hasLength(1));
      expect(delivery.summaries.single.count, 2);
      expect(delivery.summaries.single.accountId, 'work');
      expect(delivery.summaries.single.roomId, '!team:example.org');
      expect(coordinator.activePresentations, hasLength(2));
    },
  );

  test(
    'same room id in another account never shares a summary group',
    () async {
      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: delivery,
      );

      await coordinator.upsert(
        notification: notification(id: 'work-message'),
        content: content('work-message'),
      );
      await coordinator.upsert(
        notification: notification(
          id: 'personal-message',
          accountId: 'personal',
        ),
        content: content('personal-message'),
      );

      expect(delivery.summaries, isEmpty);
      expect(
        coordinator.activePresentations.map((entry) => entry.groupKey).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'privacy refresh reissues active notifications without leaking content',
    () async {
      final privacy = FakeNotificationPrivacyPort();
      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: privacy,
        delivery: delivery,
      );

      await coordinator.upsert(
        notification: notification(id: 'private'),
        content: const KiteNotificationContent(
          title: 'Alice',
          body: 'Sensitive launch details',
        ),
      );
      expect(delivery.shown.last.body, 'Sensitive launch details');

      privacy.hideNotificationContents = true;
      await coordinator.refreshPrivacy();

      expect(
        delivery.shown.last.title,
        NotificationPresentationPolicy.privateTitle,
      );
      expect(
        delivery.shown.last.body,
        NotificationPresentationPolicy.privateBody,
      );
      expect(delivery.shown.last.contentsHidden, isTrue);
      expect(delivery.shown.last.body, isNot(contains('launch')));
    },
  );

  test(
    'failed private refresh cancels stale sensitive platform content',
    () async {
      final privacy = FakeNotificationPrivacyPort();
      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: privacy,
        delivery: delivery,
      );
      await coordinator.upsert(
        notification: notification(id: 'private'),
        content: const KiteNotificationContent(
          title: 'Alice',
          body: 'Sensitive launch details',
        ),
      );
      privacy.hideNotificationContents = true;
      delivery.failNextWith = StateError('replacement failed');

      await expectLater(coordinator.refreshPrivacy(), throwsStateError);

      expect(delivery.cancelledIds, <String>['private']);
      expect(coordinator.activePresentations, isEmpty);
      expect(delivery.shown.last.body, 'Sensitive launch details');
    },
  );

  test(
    'cancel collapses summaries and failed delivery does not become active',
    () async {
      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: FakeNotificationPrivacyPort(),
        delivery: delivery,
      );

      await coordinator.upsert(
        notification: notification(id: 'one'),
        content: content('one'),
      );
      await coordinator.upsert(
        notification: notification(id: 'two'),
        content: content('two'),
      );
      final groupKey = notification(id: 'one').groupKey;

      expect(await coordinator.cancel('one'), isTrue);
      expect(delivery.cancelledIds, <String>['one']);
      expect(delivery.cancelledSummaryGroupKeys, <String>[groupKey]);
      expect(coordinator.activePresentations, hasLength(1));

      delivery.failNextWith = StateError('platform delivery failed');
      await expectLater(
        coordinator.upsert(
          notification: notification(id: 'failed'),
          content: content('failed'),
        ),
        throwsStateError,
      );
      expect(
        coordinator.activePresentations.map((entry) => entry.notification.id),
        <String>['two'],
      );
      expect(await coordinator.cancel('missing'), isFalse);
    },
  );
}
