import 'package:kite/features/navigation/app_destination.dart';

enum KiteNotificationKind { message, mention, invite, thread, call }

final class KiteNotification {
  const KiteNotification({
    required this.id,
    required this.kind,
    required this.destination,
  });

  final String id;
  final KiteNotificationKind kind;
  final AppDestination destination;

  bool get clearsWhenRead => switch (kind) {
    KiteNotificationKind.message ||
    KiteNotificationKind.mention ||
    KiteNotificationKind.thread => true,
    KiteNotificationKind.invite || KiteNotificationKind.call => false,
  };
}

abstract interface class NotificationRepository {
  KiteNotification? notification(String id);

  Iterable<KiteNotification> activeForAccount(String accountId);

  void remove(String id);
}

final class NotificationCoordinator {
  factory NotificationCoordinator({
    required NotificationRepository notifications,
    required AccountActivationPort accounts,
    required AppNavigationPort navigation,
  }) => NotificationCoordinator._(notifications, accounts, navigation);

  const NotificationCoordinator._(
    this._notifications,
    this._accounts,
    this._navigation,
  );

  final NotificationRepository _notifications;
  final AccountActivationPort _accounts;
  final AppNavigationPort _navigation;

  Future<bool> tap(String notificationId) async {
    final notification = _notifications.notification(notificationId);
    if (notification == null) return false;

    final destination = notification.destination;
    if (_accounts.activeAccountId != destination.accountId) {
      await _accounts.activateAccount(destination.accountId);
    }
    await _navigation.open(destination);
    return true;
  }

  int markRoomRead({required String accountId, required String roomId}) {
    final idsToRemove = _notifications
        .activeForAccount(accountId)
        .where(
          (notification) =>
              notification.clearsWhenRead &&
              notification.destination.roomId == roomId,
        )
        .map((notification) => notification.id)
        .toList(growable: false);

    for (final id in idsToRemove) {
      _notifications.remove(id);
    }
    return idsToRemove.length;
  }

  int reconcileReadEvents({
    required String accountId,
    required Iterable<String> eventIds,
  }) {
    final readEventIds = eventIds.toSet();
    if (readEventIds.isEmpty) return 0;

    final idsToRemove = _notifications
        .activeForAccount(accountId)
        .where(
          (notification) =>
              notification.clearsWhenRead &&
              notification.destination.eventId != null &&
              readEventIds.contains(notification.destination.eventId),
        )
        .map((notification) => notification.id)
        .toList(growable: false);

    for (final id in idsToRemove) {
      _notifications.remove(id);
    }
    return idsToRemove.length;
  }
}
