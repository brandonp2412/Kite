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
