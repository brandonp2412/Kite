import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';

final class FakeNotificationRepository
    implements MutableNotificationRepository, NotificationRegistrationPort {
  FakeNotificationRepository([Iterable<KiteNotification> initial = const []])
    : _notifications = <String, KiteNotification>{
        for (final notification in initial) notification.id: notification,
      };

  final Map<String, KiteNotification> _notifications;
  final List<String> removedIds = <String>[];

  void add(KiteNotification notification) {
    upsertNotification(notification);
  }

  @override
  void upsertNotification(KiteNotification notification) {
    upsert(notification);
  }

  @override
  void upsert(KiteNotification notification) {
    _notifications[notification.id] = notification;
  }

  @override
  Iterable<KiteNotification> activeForAccount(String accountId) {
    return _notifications.values.where(
      (notification) => notification.destination.accountId == accountId,
    );
  }

  @override
  KiteNotification? notification(String id) => _notifications[id];

  @override
  void remove(String id) {
    if (_notifications.remove(id) != null) {
      removedIds.add(id);
    }
  }
}

final class FakeNotificationCancellationPort
    implements NotificationCancellationPort {
  final List<String> cancelledIds = <String>[];
  Object? failNextWith;

  @override
  Future<bool> cancel(String notificationId) async {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    cancelledIds.add(notificationId);
    return true;
  }
}

final class FakeNotificationPrivacyPort implements NotificationPrivacyPort {
  FakeNotificationPrivacyPort({this.hideNotificationContents = false});

  @override
  bool hideNotificationContents;
}

final class FakeNotificationDeliveryPort implements NotificationDeliveryPort {
  final List<KiteNotificationPresentation> shown =
      <KiteNotificationPresentation>[];
  final List<KiteNotificationSummary> summaries = <KiteNotificationSummary>[];
  final List<String> cancelledIds = <String>[];
  final List<String> cancelledSummaryGroupKeys = <String>[];
  Object? failNextWith;

  @override
  Future<void> show(KiteNotificationPresentation presentation) async {
    _throwIfNeeded();
    shown.add(presentation);
  }

  @override
  Future<void> cancel(String notificationId) async {
    _throwIfNeeded();
    cancelledIds.add(notificationId);
  }

  @override
  Future<void> showSummary(KiteNotificationSummary summary) async {
    _throwIfNeeded();
    summaries.add(summary);
  }

  @override
  Future<void> cancelSummary(String groupKey) async {
    _throwIfNeeded();
    cancelledSummaryGroupKeys.add(groupKey);
  }

  void _throwIfNeeded() {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
  }
}

final class FakeAccountActivationPort implements AccountActivationPort {
  FakeAccountActivationPort([this._activeAccountId]);

  String? _activeAccountId;
  final List<String> activations = <String>[];

  @override
  String? get activeAccountId => _activeAccountId;

  @override
  Future<void> activateAccount(String accountId) async {
    activations.add(accountId);
    _activeAccountId = accountId;
  }
}

final class FakeAppNavigationPort implements AppNavigationPort {
  final List<AppDestination> opened = <AppDestination>[];

  @override
  Future<void> open(AppDestination destination) async {
    opened.add(destination);
  }
}
