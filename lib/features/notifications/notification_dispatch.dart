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

typedef CallNotificationHandler = Future<bool> Function(
  KiteNotification notification,
);

typedef CallNotificationErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

abstract interface class NotificationDispatchPolicyPort {
  bool allows({
    required MatrixNotificationEvent event,
    required KiteNotification notification,
  });
}

final class AllowAllNotificationDispatchPolicy
    implements NotificationDispatchPolicyPort {
  const AllowAllNotificationDispatchPolicy();

  @override
  bool allows({
    required MatrixNotificationEvent event,
    required KiteNotification notification,
  }) => true;
}

final class NotificationDispatchCoordinator {
  NotificationDispatchCoordinator({
    required NotificationRegistrationPort notifications,
    required NotificationDeliveryCoordinator delivery,
    NotificationDispatchPolicyPort policy =
        const AllowAllNotificationDispatchPolicy(),
    CallNotificationHandler? onCallNotification,
    CallNotificationErrorHandler? onCallNotificationError,
  }) : this._(
         notifications,
         delivery,
         policy,
         onCallNotification,
         onCallNotificationError,
       );

  const NotificationDispatchCoordinator._(
    this._notifications,
    this._delivery,
    this._policy,
    this._onCallNotification,
    this._onCallNotificationError,
  );

  final NotificationRegistrationPort _notifications;
  final NotificationDeliveryCoordinator _delivery;
  final NotificationDispatchPolicyPort _policy;
  final CallNotificationHandler? _onCallNotification;
  final CallNotificationErrorHandler? _onCallNotificationError;

  Future<KiteNotificationPresentation?> dispatch(
    MatrixNotificationEvent event,
  ) async {
    final notification = _notificationFor(event);
    if (!_policy.allows(event: event, notification: notification)) return null;
    if (notification.kind == KiteNotificationKind.call &&
        !await _admitCallNotification(notification)) {
      return null;
    }
    final presentation = await _delivery.upsert(
      notification: notification,
      content: KiteNotificationContent(title: event.title, body: event.body),
    );
    _notifications.upsertNotification(notification);
    return presentation;
  }

  Future<bool> _admitCallNotification(KiteNotification notification) async {
    final handler = _onCallNotification;
    if (handler == null) return true;
    try {
      return await handler(notification);
    } catch (error, stackTrace) {
      _onCallNotificationError?.call(error, stackTrace);
      return false;
    }
  }

  KiteNotification _notificationFor(MatrixNotificationEvent event) {
    _requireAccountId(event.accountId);
    _requireRoomId(event.roomId);
    _rejectUnexpectedTargetFields(event);

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

  void _requireAccountId(String accountId) {
    if (accountId.trim().isEmpty || accountId != accountId.trim()) {
      throw ArgumentError.value(
        accountId,
        'event.accountId',
        'Notifications require an exact non-empty account id.',
      );
    }
  }

  void _requireRoomId(String roomId) {
    if (!roomId.startsWith('!') ||
        roomId.length <= 2 ||
        !roomId.contains(':') ||
        roomId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        roomId,
        'event.roomId',
        'Notifications require an exact Matrix room id.',
      );
    }
  }

  void _rejectUnexpectedTargetFields(MatrixNotificationEvent event) {
    final hasUnexpectedField = switch (event.kind) {
      MatrixNotificationEventKind.message ||
      MatrixNotificationEventKind.mention =>
        event.threadRootEventId != null || event.callId != null,
      MatrixNotificationEventKind.invite =>
        event.eventId != null ||
            event.threadRootEventId != null ||
            event.callId != null,
      MatrixNotificationEventKind.thread => event.callId != null,
      MatrixNotificationEventKind.call =>
        event.eventId != null || event.threadRootEventId != null,
    };
    if (hasUnexpectedField) {
      throw ArgumentError.value(
        event.kind,
        'event.kind',
        'Notification target fields do not match the event kind.',
      );
    }
  }

  String _requiredEventId(MatrixNotificationEvent event) {
    final eventId = event.eventId;
    if (eventId == null ||
        !eventId.startsWith(r'$') ||
        eventId.length <= 1 ||
        eventId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        event.eventId,
        'event.eventId',
        'Message, mention, and thread notifications require an exact Matrix event id.',
      );
    }
    return eventId;
  }

  String _requiredThreadRootEventId(MatrixNotificationEvent event) {
    final rootId = event.threadRootEventId;
    if (rootId == null ||
        !rootId.startsWith(r'$') ||
        rootId.length <= 1 ||
        rootId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        event.threadRootEventId,
        'event.threadRootEventId',
        'Thread notifications require an exact Matrix thread root event id.',
      );
    }
    return rootId;
  }

  String _requiredCallId(MatrixNotificationEvent event) {
    final callId = event.callId;
    if (callId == null ||
        callId.isEmpty ||
        callId != callId.trim() ||
        callId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        event.callId,
        'event.callId',
        'Call notifications require an exact MatrixRTC call id.',
      );
    }
    return callId;
  }
}
