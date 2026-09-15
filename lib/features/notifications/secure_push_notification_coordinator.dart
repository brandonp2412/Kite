import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/push_registration.dart';

final class SecurePushNotificationCoordinator {
  factory SecurePushNotificationCoordinator({
    required PushRegistrationController pushRegistration,
    required MutableNotificationRepository notifications,
    required NotificationDeliveryCoordinator delivery,
    required NotificationBadgeRefreshPort badgeRefresh,
  }) => SecurePushNotificationCoordinator._(
    pushRegistration,
    notifications,
    delivery,
    badgeRefresh,
  );

  const SecurePushNotificationCoordinator._(
    this._pushRegistration,
    this._notifications,
    this._delivery,
    this._badgeRefresh,
  );

  final PushRegistrationController _pushRegistration;
  final MutableNotificationRepository _notifications;
  final NotificationDeliveryCoordinator _delivery;
  final NotificationBadgeRefreshPort _badgeRefresh;

  Future<bool> handleEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) async {
    final decoded = await _pushRegistration.processEncryptedPayload(
      accountId: accountId,
      encryptedPayload: encryptedPayload,
    );
    if (decoded == null || !_isValidNotification(decoded.notification)) {
      return false;
    }

    final previous = _notifications.notification(decoded.notification.id);
    _notifications.upsert(decoded.notification);
    try {
      await _delivery.upsert(
        notification: decoded.notification,
        content: decoded.content,
      );
    } catch (_) {
      _restorePrevious(previous, decoded.notification.id);
      return false;
    }

    try {
      await _badgeRefresh.refreshBadgeCount();
    } catch (_) {
      // Badge updates are best-effort. A platform badge failure must not drop a
      // securely decoded and already-delivered notification.
    }
    return true;
  }

  bool _isValidNotification(KiteNotification notification) {
    final destination = notification.destination;
    return notification.id.trim().isNotEmpty &&
        notification.id == notification.id.trim() &&
        destination.accountId.trim().isNotEmpty &&
        destination.roomId.trim().isNotEmpty;
  }

  void _restorePrevious(KiteNotification? previous, String failedId) {
    if (previous == null) {
      _notifications.remove(failedId);
    } else {
      _notifications.upsert(previous);
    }
  }
}
