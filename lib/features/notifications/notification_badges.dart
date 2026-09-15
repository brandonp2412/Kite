import 'package:kite/features/notifications/notification_routing.dart';

abstract interface class NotificationBadgePort {
  Future<void> setBadgeCount(int count);
}

final class NotificationBadgeCoordinator {
  factory NotificationBadgeCoordinator({
    required NotificationRepository notifications,
    required NotificationBadgePort badges,
  }) => NotificationBadgeCoordinator._(notifications, badges);

  const NotificationBadgeCoordinator._(this._notifications, this._badges);

  final NotificationRepository _notifications;
  final NotificationBadgePort _badges;

  Future<int> refreshForAccounts(Iterable<String> accountIds) async {
    final normalized = <String>{
      for (final accountId in accountIds)
        if (accountId.trim().isNotEmpty) accountId.trim(),
    };
    final notificationIds = <String>{};
    for (final accountId in normalized) {
      for (final notification in _notifications.activeForAccount(accountId)) {
        if (_countsTowardBadge(notification)) {
          notificationIds.add(notification.id);
        }
      }
    }
    final count = notificationIds.length;
    await _badges.setBadgeCount(count);
    return count;
  }

  Future<int> clear() async {
    await _badges.setBadgeCount(0);
    return 0;
  }

  bool _countsTowardBadge(KiteNotification notification) =>
      switch (notification.kind) {
        KiteNotificationKind.message ||
        KiteNotificationKind.mention ||
        KiteNotificationKind.invite ||
        KiteNotificationKind.thread ||
        KiteNotificationKind.call => true,
      };
}

final class AllAccountNotificationBadgeRefresher
    implements NotificationBadgeRefreshPort {
  factory AllAccountNotificationBadgeRefresher({
    required NotificationBadgeCoordinator coordinator,
    required Iterable<String> Function() accountIds,
  }) => AllAccountNotificationBadgeRefresher._(coordinator, accountIds);

  const AllAccountNotificationBadgeRefresher._(
    this._coordinator,
    this._accountIds,
  );

  final NotificationBadgeCoordinator _coordinator;
  final Iterable<String> Function() _accountIds;

  @override
  Future<void> refreshBadgeCount() =>
      _coordinator.refreshForAccounts(_accountIds());
}
