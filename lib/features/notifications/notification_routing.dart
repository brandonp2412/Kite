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

  String get routingId => routingIdFor(destination.accountId, id);

  static String routingIdFor(String accountId, String id) =>
      '${accountId.length}:$accountId${id.length}:$id';

  bool get clearsWhenRead => switch (kind) {
    KiteNotificationKind.message ||
    KiteNotificationKind.mention ||
    KiteNotificationKind.thread => true,
    KiteNotificationKind.invite || KiteNotificationKind.call => false,
  };

  String get groupKey =>
      '${destination.accountId.length}:${destination.accountId}'
      '${destination.roomId.length}:${destination.roomId}';
}

final class KiteNotificationContent {
  const KiteNotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

final class KiteNotificationPresentation {
  const KiteNotificationPresentation({
    required this.notification,
    required this.title,
    required this.body,
    required this.contentsHidden,
  });

  final KiteNotification notification;
  final String title;
  final String body;
  final bool contentsHidden;

  String get groupKey => notification.groupKey;
}

final class KiteNotificationSummary {
  const KiteNotificationSummary({
    required this.groupKey,
    required this.accountId,
    required this.roomId,
    required this.count,
    required this.contentsHidden,
  });

  final String groupKey;
  final String accountId;
  final String roomId;
  final int count;
  final bool contentsHidden;
}

final class NotificationPresentationPolicy {
  const NotificationPresentationPolicy();

  static const String privateTitle = 'Kite';
  static const String privateBody = 'New notification';

  KiteNotificationPresentation present({
    required KiteNotification notification,
    required KiteNotificationContent content,
    required bool hideContents,
  }) {
    return KiteNotificationPresentation(
      notification: notification,
      title: hideContents ? privateTitle : content.title,
      body: hideContents ? privateBody : content.body,
      contentsHidden: hideContents,
    );
  }

  List<KiteNotificationSummary> summaries(
    Iterable<KiteNotificationPresentation> presentations,
  ) {
    final groups = <String, List<KiteNotificationPresentation>>{};
    for (final presentation in presentations) {
      groups
          .putIfAbsent(
            presentation.groupKey,
            () => <KiteNotificationPresentation>[],
          )
          .add(presentation);
    }

    return List<KiteNotificationSummary>.unmodifiable(
      groups.values.map((group) {
        final destination = group.first.notification.destination;
        return KiteNotificationSummary(
          groupKey: group.first.groupKey,
          accountId: destination.accountId,
          roomId: destination.roomId,
          count: group.length,
          contentsHidden: group.any((entry) => entry.contentsHidden),
        );
      }),
    );
  }
}

abstract interface class NotificationRepository {
  KiteNotification? notification(String routingId);

  Iterable<KiteNotification> activeForAccount(String accountId);

  void remove(String routingId);
}

abstract interface class MutableNotificationRepository
    implements NotificationRepository {
  void upsert(KiteNotification notification);
}

abstract interface class NotificationCancellationPort {
  Future<bool> cancel(String notificationId);
}

abstract interface class NotificationBadgeRefreshPort {
  Future<void> refreshBadgeCount();
}

final class NotificationCoordinator {
  factory NotificationCoordinator({
    required NotificationRepository notifications,
    required NotificationCancellationPort cancellations,
    required AccountActivationPort accounts,
    required AppNavigationPort navigation,
    NotificationBadgeRefreshPort? badgeRefresh,
  }) => NotificationCoordinator._(
    notifications,
    cancellations,
    accounts,
    navigation,
    badgeRefresh,
  );

  const NotificationCoordinator._(
    this._notifications,
    this._cancellations,
    this._accounts,
    this._navigation,
    this._badgeRefresh,
  );

  final NotificationRepository _notifications;
  final NotificationCancellationPort _cancellations;
  final AccountActivationPort _accounts;
  final AppNavigationPort _navigation;
  final NotificationBadgeRefreshPort? _badgeRefresh;

  Future<bool> tap(String notificationRoutingId) async {
    final notification = _notifications.notification(notificationRoutingId);
    if (notification == null) return false;

    final destination = notification.destination;
    try {
      if (_accounts.activeAccountId != destination.accountId) {
        await _accounts.activateAccount(destination.accountId);
        if (_accounts.activeAccountId != destination.accountId) return false;
      }
      await _navigation.open(destination);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> markRoomRead({
    required String accountId,
    required String roomId,
  }) async {
    final idsToRemove = _notifications
        .activeForAccount(accountId)
        .where(
          (notification) =>
              notification.clearsWhenRead &&
              notification.destination.roomId == roomId,
        )
        .map((notification) => notification.routingId)
        .toList(growable: false);

    return _cancelAndRemove(idsToRemove);
  }

  Future<int> reconcileReadEvents({
    required String accountId,
    required Iterable<String> eventIds,
  }) async {
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
        .map((notification) => notification.routingId)
        .toList(growable: false);

    return _cancelAndRemove(idsToRemove);
  }

  Future<int> _cancelAndRemove(Iterable<String> notificationIds) async {
    var removed = 0;
    for (final id in notificationIds) {
      final cancelled = await _cancellations.cancel(id);
      if (!cancelled) continue;
      _notifications.remove(id);
      removed += 1;
    }
    if (removed > 0) {
      await _badgeRefresh?.refreshBadgeCount();
    }
    return removed;
  }
}
