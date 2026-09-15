import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';

enum NotificationIngressTransport { fcm, backgroundSync }

enum NotificationIngressFailure {
  missingNotificationId,
  missingKind,
  unsupportedKind,
  missingAccountId,
  missingRoomId,
  missingEventId,
  missingThreadRootEventId,
  missingCallId,
  unexpectedTargetField,
}

final class NotificationIngressResult {
  const NotificationIngressResult.accepted({
    required this.transport,
    required KiteNotification this.notification,
  }) : failure = null;

  const NotificationIngressResult.rejected({
    required this.transport,
    required NotificationIngressFailure this.failure,
  }) : notification = null;

  final NotificationIngressTransport transport;
  final KiteNotification? notification;
  final NotificationIngressFailure? failure;

  bool get accepted => notification != null;
}

final class NotificationIngressParser {
  const NotificationIngressParser();

  NotificationIngressResult parse({
    required NotificationIngressTransport transport,
    required Map<String, String?> data,
  }) {
    final notificationId = _value(data, 'notification_id');
    if (notificationId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingNotificationId,
      );
    }
    final rawKind = _value(data, 'kind');
    if (rawKind == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingKind,
      );
    }
    final kind = switch (rawKind) {
      'message' => KiteNotificationKind.message,
      'mention' => KiteNotificationKind.mention,
      'invite' => KiteNotificationKind.invite,
      'thread' => KiteNotificationKind.thread,
      'call' => KiteNotificationKind.call,
      _ => null,
    };
    if (kind == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.unsupportedKind,
      );
    }
    final accountId = _value(data, 'account_id');
    if (accountId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingAccountId,
      );
    }
    final roomId = _value(data, 'room_id');
    if (roomId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingRoomId,
      );
    }

    final eventId = _value(data, 'event_id');
    final threadRootEventId = _value(data, 'thread_root_event_id');
    final callId = _value(data, 'call_id');
    final destination = switch (kind) {
      KiteNotificationKind.message || KiteNotificationKind.mention =>
        eventId == null
            ? null
            : AppDestination.event(
                accountId: accountId,
                roomId: roomId,
                eventId: eventId,
              ),
      KiteNotificationKind.invite => AppDestination.room(
        accountId: accountId,
        roomId: roomId,
      ),
      KiteNotificationKind.thread =>
        eventId == null || threadRootEventId == null
            ? null
            : AppDestination.thread(
                accountId: accountId,
                roomId: roomId,
                eventId: eventId,
                threadRootEventId: threadRootEventId,
              ),
      KiteNotificationKind.call =>
        callId == null
            ? null
            : AppDestination.call(
                accountId: accountId,
                roomId: roomId,
                callId: callId,
              ),
    };
    if (destination == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: switch (kind) {
          KiteNotificationKind.message || KiteNotificationKind.mention =>
            NotificationIngressFailure.missingEventId,
          KiteNotificationKind.thread when eventId == null =>
            NotificationIngressFailure.missingEventId,
          KiteNotificationKind.thread =>
            NotificationIngressFailure.missingThreadRootEventId,
          KiteNotificationKind.call => NotificationIngressFailure.missingCallId,
          KiteNotificationKind.invite =>
            NotificationIngressFailure.unexpectedTargetField,
        },
      );
    }

    final hasUnexpectedTargetField = switch (kind) {
      KiteNotificationKind.message || KiteNotificationKind.mention =>
        threadRootEventId != null || callId != null,
      KiteNotificationKind.invite =>
        eventId != null || threadRootEventId != null || callId != null,
      KiteNotificationKind.thread => callId != null,
      KiteNotificationKind.call => eventId != null || threadRootEventId != null,
    };
    if (hasUnexpectedTargetField) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.unexpectedTargetField,
      );
    }

    return NotificationIngressResult.accepted(
      transport: transport,
      notification: KiteNotification(
        id: notificationId,
        kind: kind,
        destination: destination,
      ),
    );
  }

  static String? _value(Map<String, String?> data, String key) {
    final value = data[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

typedef NotificationIngressHandler = Future<void> Function(
  NotificationIngressResult result,
);

final class NotificationIngressCoordinator {
  const NotificationIngressCoordinator({
    required this.onAccepted,
    this.parser = const NotificationIngressParser(),
  });

  final NotificationIngressHandler onAccepted;
  final NotificationIngressParser parser;

  Future<NotificationIngressResult> receive({
    required NotificationIngressTransport transport,
    required Map<String, String?> data,
  }) async {
    final result = parser.parse(transport: transport, data: data);
    if (result.accepted) {
      await onAccepted(result);
    }
    return result;
  }
}
