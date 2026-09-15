import 'package:kite/features/navigation/app_destination.dart';
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

    final routingId = decoded.notification.routingId;
    final previous = _notifications.notification(routingId);
    _notifications.upsert(decoded.notification);
    try {
      await _delivery.upsert(
        notification: decoded.notification,
        content: decoded.content,
      );
    } catch (_) {
      _restorePrevious(previous, routingId);
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
    if (notification.id.trim().isEmpty ||
        notification.id != notification.id.trim() ||
        destination.accountId.trim().isEmpty ||
        destination.accountId != destination.accountId.trim() ||
        !_isValidRoomId(destination.roomId) ||
        !_kindMatchesDestination(notification.kind, destination.kind)) {
      return false;
    }
    return switch (destination.kind) {
      AppDestinationKind.room =>
        destination.eventId == null &&
            destination.threadRootEventId == null &&
            destination.callId == null,
      AppDestinationKind.event =>
        _isValidEventId(destination.eventId) &&
            destination.threadRootEventId == null &&
            destination.callId == null,
      AppDestinationKind.thread =>
        _isValidEventId(destination.eventId) &&
            _isValidEventId(destination.threadRootEventId) &&
            destination.callId == null,
      AppDestinationKind.call =>
        destination.eventId == null &&
            destination.threadRootEventId == null &&
            _isValidOpaqueId(destination.callId),
    };
  }

  bool _kindMatchesDestination(
    KiteNotificationKind notificationKind,
    AppDestinationKind destinationKind,
  ) {
    return switch (notificationKind) {
      KiteNotificationKind.message || KiteNotificationKind.mention =>
        destinationKind == AppDestinationKind.event,
      KiteNotificationKind.invite => destinationKind == AppDestinationKind.room,
      KiteNotificationKind.thread =>
        destinationKind == AppDestinationKind.thread,
      KiteNotificationKind.call => destinationKind == AppDestinationKind.call,
    };
  }

  bool _isValidRoomId(String roomId) {
    final trimmed = roomId.trim();
    final separator = trimmed.indexOf(':');
    return trimmed == roomId &&
        trimmed.startsWith('!') &&
        separator > 1 &&
        separator < trimmed.length - 1 &&
        !trimmed.contains(RegExp(r'\s'));
  }

  bool _isValidEventId(String? eventId) {
    if (eventId == null) return false;
    final trimmed = eventId.trim();
    return trimmed == eventId &&
        trimmed.startsWith(r'$') &&
        trimmed.length > 1 &&
        !trimmed.contains(RegExp(r'\s'));
  }

  bool _isValidOpaqueId(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed == value &&
        trimmed.isNotEmpty &&
        !trimmed.contains(RegExp(r'\s'));
  }

  void _restorePrevious(KiteNotification? previous, String failedRoutingId) {
    if (previous == null) {
      _notifications.remove(failedRoutingId);
    } else {
      _notifications.upsert(previous);
    }
  }
}
