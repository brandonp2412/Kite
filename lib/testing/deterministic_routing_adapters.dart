import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';

final class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository([Iterable<KiteNotification> initial = const []])
    : _notifications = <String, KiteNotification>{
        for (final notification in initial) notification.id: notification,
      };

  final Map<String, KiteNotification> _notifications;
  final List<String> removedIds = <String>[];

  void add(KiteNotification notification) {
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
