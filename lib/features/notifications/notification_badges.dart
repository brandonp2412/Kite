import 'dart:async';

import 'package:kite/features/notifications/notification_routing.dart';

abstract interface class NotificationBadgePort {
  Future<void> setBadgeCount(int count);
}

final class NotificationBadgeCoordinator {
  factory NotificationBadgeCoordinator({
    required NotificationRepository notifications,
    required NotificationBadgePort badges,
  }) => NotificationBadgeCoordinator._(notifications, badges);

  NotificationBadgeCoordinator._(this._notifications, this._badges);

  final NotificationRepository _notifications;
  final NotificationBadgePort _badges;
  Future<void> _pendingUpdate = Future<void>.value();

  Future<int> refreshForAccounts(Iterable<String> accountIds) {
    final normalized = <String>{
      for (final accountId in accountIds)
        if (accountId.trim().isNotEmpty) accountId.trim(),
    };
    return _enqueue(() async {
      final notificationIds = <String>{};
      for (final accountId in normalized) {
        for (final notification in _notifications.activeForAccount(accountId)) {
          if (_countsTowardBadge(notification)) {
            notificationIds.add(notification.routingId);
          }
        }
      }
      final count = notificationIds.length;
      await _badges.setBadgeCount(count);
      return count;
    });
  }

  Future<int> clear() {
    return _enqueue(() async {
      await _badges.setBadgeCount(0);
      return 0;
    });
  }

  Future<int> _enqueue(Future<int> Function() update) {
    final completion = Completer<int>();
    _pendingUpdate = _pendingUpdate.then((_) async {
      try {
        completion.complete(await update());
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
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
