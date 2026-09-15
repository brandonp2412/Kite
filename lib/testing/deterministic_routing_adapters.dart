import 'dart:async';

import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_resolution.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/notification_settings_policy.dart';
import 'package:kite/features/notifications/notification_transport.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class FakeNotificationRepository
    implements MutableNotificationRepository, NotificationRegistrationPort {
  FakeNotificationRepository([Iterable<KiteNotification> initial = const []])
    : _notifications = <String, KiteNotification>{
        for (final notification in initial)
          notification.routingId: notification,
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
    _notifications[notification.routingId] = notification;
  }

  @override
  Iterable<KiteNotification> activeForAccount(String accountId) {
    return _notifications.values.where(
      (notification) => notification.destination.accountId == accountId,
    );
  }

  @override
  KiteNotification? notification(String routingId) => _notifications[routingId];

  @override
  void remove(String routingId) {
    if (_notifications.remove(routingId) != null) {
      removedIds.add(routingId);
    }
  }
}

final class FakeNotificationCancellationPort
    implements NotificationCancellationPort {
  final List<String> cancelledIds = <String>[];
  Object? failNextWith;
  bool succeeds = true;

  @override
  Future<bool> cancel(String notificationId) async {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    if (!succeeds) return false;
    cancelledIds.add(notificationId);
    return true;
  }
}

final class FakeNotificationEventResolver
    implements NotificationEventResolverPort {
  MatrixNotificationEvent? event;
  final Map<String, MatrixNotificationEvent> eventsByRoutingId =
      <String, MatrixNotificationEvent>{};
  Object? failNextWith;
  final List<KiteNotification> resolutions = <KiteNotification>[];

  @override
  Future<MatrixNotificationEvent?> resolve(
    KiteNotification notification,
  ) async {
    resolutions.add(notification);
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    return eventsByRoutingId[notification.routingId] ?? event;
  }
}

final class FakeNotificationPreferencesSource
    implements NotificationPreferencesSourcePort {
  FakeNotificationPreferencesSource([
    this.notificationPreferences = const NotificationPreferences.defaults(),
  ]);

  @override
  NotificationPreferences notificationPreferences;
}

final class FakeNotificationDispatchPolicy
    implements NotificationDispatchPolicyPort {
  bool allow = true;
  final List<String> evaluatedIds = <String>[];

  @override
  bool allows({
    required MatrixNotificationEvent event,
    required KiteNotification notification,
  }) {
    evaluatedIds.add(notification.id);
    return allow;
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
  Object? failNextSummaryWith;
  Object? failNextCancelSummaryWith;

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
    final summaryFailure = failNextSummaryWith;
    failNextSummaryWith = null;
    if (summaryFailure != null) throw summaryFailure;
    _throwIfNeeded();
    summaries.add(summary);
  }

  @override
  Future<void> cancelSummary(String groupKey) async {
    final summaryFailure = failNextCancelSummaryWith;
    failNextCancelSummaryWith = null;
    if (summaryFailure != null) throw summaryFailure;
    _throwIfNeeded();
    cancelledSummaryGroupKeys.add(groupKey);
  }

  void _throwIfNeeded() {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
  }
}

final class FakeNotificationPayloadSource
    implements NotificationPayloadSourcePort {
  final StreamController<Map<String, String?>> _controller =
      StreamController<Map<String, String?>>.broadcast(sync: true);

  @override
  Stream<Map<String, String?>> get payloads => _controller.stream;

  void emit(Map<String, String?> payload) {
    _controller.add(Map<String, String?>.of(payload));
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace);
  }

  Future<void> close() => _controller.close();
}

final class FakeNotificationIngressAccountPort
    implements NotificationIngressAccountPort {
  FakeNotificationIngressAccountPort(Iterable<String> accountIds)
    : accountIds = Set<String>.of(accountIds);

  final Set<String> accountIds;
  final List<String> queries = <String>[];

  @override
  Future<bool> containsAccount(String accountId) async {
    queries.add(accountId);
    return accountIds.contains(accountId);
  }
}

final class FakeAccountActivationPort implements AccountActivationPort {
  FakeAccountActivationPort([this._activeAccountId]);

  String? _activeAccountId;
  final List<String> activations = <String>[];
  bool activates = true;
  Object? failNextWith;

  @override
  String? get activeAccountId => _activeAccountId;

  @override
  Future<void> activateAccount(String accountId) async {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    activations.add(accountId);
    if (activates) _activeAccountId = accountId;
  }
}

final class FakeAppNavigationPort implements AppNavigationPort {
  final List<AppDestination> opened = <AppDestination>[];
  Object? failNextWith;

  @override
  Future<void> open(AppDestination destination) async {
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    opened.add(destination);
  }
}
