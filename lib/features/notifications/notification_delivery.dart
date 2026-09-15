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
    final routingId = notification.routingId;
    final previous = _active[routingId];

    await _delivery.show(presentation);
    _active[routingId] = next;

    try {
      if (previous != null &&
          previous.notification.groupKey != notification.groupKey) {
        await _refreshSummary(previous.notification.groupKey);
      }
      await _refreshSummary(notification.groupKey);
    } catch (_) {
      await _rollbackUpsert(
        routingId: routingId,
        previous: previous,
        failed: next,
      );
      rethrow;
    }
    return presentation;
  }

  @override
  Future<bool> cancel(String notificationRoutingId) async {
    final current = _active[notificationRoutingId];
    if (current == null) return false;

    await _delivery.cancel(notificationRoutingId);
    _active.remove(notificationRoutingId);
    await _refreshSummary(current.notification.groupKey);
    return true;
  }

  Future<void> refreshPrivacy() async {
    Object? firstFailure;
    final activeEntries = List<_ActiveNotification>.of(_active.values);
    for (final active in activeEntries) {
      try {
        await _delivery.show(_presentationFor(active));
      } catch (error) {
        firstFailure ??= error;
        if (_privacy.hideNotificationContents) {
          try {
            await _delivery.cancel(active.notification.routingId);
            _active.remove(active.notification.routingId);
          } catch (_) {}
        }
      }
    }
    for (final groupKey in _groupKeys()) {
      await _refreshSummary(groupKey);
    }
    if (firstFailure != null) throw firstFailure;
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
      if (_activeSummaryGroups.contains(groupKey)) {
        await _delivery.cancelSummary(groupKey);
        _activeSummaryGroups.remove(groupKey);
      }
      return;
    }

    final summary = _policy.summaries(group).single;
    await _delivery.showSummary(summary);
    _activeSummaryGroups.add(groupKey);
  }

  Future<void> _rollbackUpsert({
    required String routingId,
    required _ActiveNotification? previous,
    required _ActiveNotification failed,
  }) async {
    if (previous == null) {
      _active.remove(routingId);
      try {
        await _delivery.cancel(routingId);
      } catch (_) {}
    } else {
      _active[routingId] = previous;
      try {
        await _delivery.show(_presentationFor(previous));
      } catch (_) {}
    }

    final affectedGroups = <String>{
      failed.notification.groupKey,
      if (previous != null) previous.notification.groupKey,
    };
    for (final groupKey in affectedGroups) {
      try {
        await _refreshSummary(groupKey);
      } catch (_) {}
    }
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
