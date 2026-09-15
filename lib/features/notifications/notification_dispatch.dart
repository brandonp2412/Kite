import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_routing.dart';

enum MatrixNotificationEventKind { message, mention, invite, thread, call }

final class MatrixNotificationEvent {
  const MatrixNotificationEvent({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.roomId,
    required this.title,
    required this.body,
    this.eventId,
    this.threadRootEventId,
    this.callId,
  });

  final String id;
  final MatrixNotificationEventKind kind;
  final String accountId;
  final String roomId;
  final String title;
  final String body;
  final String? eventId;
  final String? threadRootEventId;
  final String? callId;
}

abstract interface class NotificationRegistrationPort {
  void upsertNotification(KiteNotification notification);
}

final class NotificationDispatchCoordinator {
  NotificationDispatchCoordinator({
    required NotificationRegistrationPort notifications,
    required NotificationDeliveryCoordinator delivery,
  }) : this._(notifications, delivery);

  const NotificationDispatchCoordinator._(this._notifications, this._delivery);

  final NotificationRegistrationPort _notifications;
  final NotificationDeliveryCoordinator _delivery;

  Future<KiteNotificationPresentation> dispatch(
    MatrixNotificationEvent event,
  ) async {
    final notification = _notificationFor(event);
    final presentation = await _delivery.upsert(
      notification: notification,
      content: KiteNotificationContent(title: event.title, body: event.body),
    );
    _notifications.upsertNotification(notification);
    return presentation;
  }

  KiteNotification _notificationFor(MatrixNotificationEvent event) {
    final destination = switch (event.kind) {
      MatrixNotificationEventKind.message ||
      MatrixNotificationEventKind.mention => AppDestination.event(
        accountId: event.accountId,
        roomId: event.roomId,
        eventId: _requiredEventId(event),
      ),
      MatrixNotificationEventKind.invite => AppDestination.room(
        accountId: event.accountId,
        roomId: event.roomId,
      ),
      MatrixNotificationEventKind.thread => AppDestination.thread(
        accountId: event.accountId,
        roomId: event.roomId,
        eventId: _requiredEventId(event),
        threadRootEventId: _requiredThreadRootEventId(event),
      ),
      MatrixNotificationEventKind.call => AppDestination.call(
        accountId: event.accountId,
        roomId: event.roomId,
        callId: _requiredCallId(event),
      ),
    };

    final kind = switch (event.kind) {
      MatrixNotificationEventKind.message => KiteNotificationKind.message,
      MatrixNotificationEventKind.mention => KiteNotificationKind.mention,
      MatrixNotificationEventKind.invite => KiteNotificationKind.invite,
      MatrixNotificationEventKind.thread => KiteNotificationKind.thread,
      MatrixNotificationEventKind.call => KiteNotificationKind.call,
    };

    return KiteNotification(id: event.id, kind: kind, destination: destination);
  }

  String _requiredEventId(MatrixNotificationEvent event) {
    final eventId = event.eventId;
    if (eventId == null || eventId.isEmpty) {
      throw ArgumentError.value(
        event.eventId,
        'event.eventId',
        'Message, mention, and thread notifications require an event id.',
      );
    }
    return eventId;
  }

  String _requiredThreadRootEventId(MatrixNotificationEvent event) {
    final rootId = event.threadRootEventId;
    if (rootId == null || rootId.isEmpty) {
      throw ArgumentError.value(
        event.threadRootEventId,
        'event.threadRootEventId',
        'Thread notifications require a thread root event id.',
      );
    }
    return rootId;
  }

  String _requiredCallId(MatrixNotificationEvent event) {
    final callId = event.callId;
    if (callId == null || callId.isEmpty) {
      throw ArgumentError.value(
        event.callId,
        'event.callId',
        'Call notifications require a MatrixRTC call id.',
      );
    }
    return callId;
  }
}
