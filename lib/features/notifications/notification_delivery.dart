import 'package:kite/features/notifications/notification_routing.dart';

abstract interface class NotificationPrivacyPort {
  bool get hideNotificationContents;
}

abstract interface class NotificationDeliveryPort {
  Future<void> show(KiteNotificationPresentation presentation);

  Future<void> cancel(String notificationId);

  Future<void> showSummary(KiteNotificationSummary summary);

  Future<void> cancelSummary(String groupKey);
}

final class NotificationDeliveryCoordinator
    implements NotificationCancellationPort {
  factory NotificationDeliveryCoordinator({
    required NotificationPrivacyPort privacy,
    required NotificationDeliveryPort delivery,
    NotificationPresentationPolicy policy =
        const NotificationPresentationPolicy(),
  }) => NotificationDeliveryCoordinator._(privacy, delivery, policy);

  NotificationDeliveryCoordinator._(
    this._privacy,
    this._delivery,
    this._policy,
  );

  final NotificationPrivacyPort _privacy;
  final NotificationDeliveryPort _delivery;
  final NotificationPresentationPolicy _policy;
  final Map<String, _ActiveNotification> _active =
      <String, _ActiveNotification>{};
  final Set<String> _activeSummaryGroups = <String>{};

  Iterable<KiteNotificationPresentation> get activePresentations =>
      List<KiteNotificationPresentation>.unmodifiable(
        _active.values.map(_presentationFor),
      );

  Future<KiteNotificationPresentation> upsert({
    required KiteNotification notification,
    required KiteNotificationContent content,
  }) async {
    final next = _ActiveNotification(
      notification: notification,
      content: content,
    );
    final presentation = _presentationFor(next);
    final previous = _active[notification.id];

    await _delivery.show(presentation);
    _active[notification.id] = next;

    if (previous != null &&
        previous.notification.groupKey != notification.groupKey) {
      await _refreshSummary(previous.notification.groupKey);
    }
    await _refreshSummary(notification.groupKey);
    return presentation;
  }

  @override
  Future<bool> cancel(String notificationId) async {
    final current = _active[notificationId];
    if (current == null) return false;

    await _delivery.cancel(notificationId);
    _active.remove(notificationId);
    await _refreshSummary(current.notification.groupKey);
    return true;
  }

  Future<void> refreshPrivacy() async {
    for (final active in _active.values) {
      await _delivery.show(_presentationFor(active));
    }
    for (final groupKey in _groupKeys()) {
      await _refreshSummary(groupKey);
    }
  }

  KiteNotificationPresentation _presentationFor(_ActiveNotification active) {
    return _policy.present(
      notification: active.notification,
      content: active.content,
      hideContents: _privacy.hideNotificationContents,
    );
  }

  Set<String> _groupKeys() => <String>{
    for (final active in _active.values) active.notification.groupKey,
    ..._activeSummaryGroups,
  };

  Future<void> _refreshSummary(String groupKey) async {
    final group = <KiteNotificationPresentation>[
      for (final active in _active.values)
        if (active.notification.groupKey == groupKey) _presentationFor(active),
    ];

    if (group.length < 2) {
      if (_activeSummaryGroups.remove(groupKey)) {
        await _delivery.cancelSummary(groupKey);
      }
      return;
    }

    final summary = _policy.summaries(group).single;
    await _delivery.showSummary(summary);
    _activeSummaryGroups.add(groupKey);
  }
}

final class _ActiveNotification {
  const _ActiveNotification({
    required this.notification,
    required this.content,
  });

  final KiteNotification notification;
  final KiteNotificationContent content;
}
