import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_routing.dart';

abstract interface class NotificationEventResolverPort {
  Future<MatrixNotificationEvent?> resolve(KiteNotification notification);
}

enum NotificationResolutionStatus { stale, suppressed, delivered }

final class NotificationResolutionResult {
  const NotificationResolutionResult(this.status);

  final NotificationResolutionStatus status;
}

final class NotificationResolutionCoordinator {
  factory NotificationResolutionCoordinator({
    required NotificationEventResolverPort resolver,
    required NotificationDispatchCoordinator dispatch,
  }) => NotificationResolutionCoordinator._(resolver, dispatch);

  const NotificationResolutionCoordinator._(this._resolver, this._dispatch);

  final NotificationEventResolverPort _resolver;
  final NotificationDispatchCoordinator _dispatch;

  Future<NotificationResolutionResult> resolveAndDispatch(
    NotificationIngressResult ingress,
  ) async {
    final notification = ingress.notification;
    if (!ingress.accepted || notification == null) {
      throw StateError('Only accepted notification ingress can be resolved.');
    }

    final event = await _resolver.resolve(notification);
    if (event == null) {
      return const NotificationResolutionResult(
        NotificationResolutionStatus.stale,
      );
    }
    _requireExactIdentity(notification, event);

    final presentation = await _dispatch.dispatch(event);
    return NotificationResolutionResult(
      presentation == null
          ? NotificationResolutionStatus.suppressed
          : NotificationResolutionStatus.delivered,
    );
  }

  Future<void> handleAccepted(NotificationIngressResult ingress) async {
    await resolveAndDispatch(ingress);
  }

  void _requireExactIdentity(
    KiteNotification notification,
    MatrixNotificationEvent event,
  ) {
    final destination = notification.destination;
    final expectedKind = switch (notification.kind) {
      KiteNotificationKind.message => MatrixNotificationEventKind.message,
      KiteNotificationKind.mention => MatrixNotificationEventKind.mention,
      KiteNotificationKind.invite => MatrixNotificationEventKind.invite,
      KiteNotificationKind.thread => MatrixNotificationEventKind.thread,
      KiteNotificationKind.call => MatrixNotificationEventKind.call,
    };
    final matchesTarget =
        event.id == notification.id &&
        event.kind == expectedKind &&
        event.accountId == destination.accountId &&
        event.roomId == destination.roomId &&
        event.eventId == destination.eventId &&
        event.threadRootEventId == destination.threadRootEventId &&
        event.callId == destination.callId;
    if (!matchesTarget) {
      throw StateError(
        'Resolved notification identity does not match the validated ingress target.',
      );
    }
  }
}
