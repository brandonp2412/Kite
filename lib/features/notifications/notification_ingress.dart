import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';

enum NotificationIngressTransport { fcm, backgroundSync }

enum NotificationIngressFailure {
  missingNotificationId,
  missingKind,
  unsupportedKind,
  missingAccountId,
  invalidAccountId,
  missingRoomId,
  invalidRoomId,
  missingEventId,
  invalidEventId,
  missingThreadRootEventId,
  invalidThreadRootEventId,
  missingCallId,
  invalidCallId,
  unexpectedTargetField,
  unknownAccount,
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
    final notificationId = _trimmedValue(data, 'notification_id');
    if (notificationId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingNotificationId,
      );
    }
    final rawKind = _trimmedValue(data, 'kind');
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
    final accountId = _exactValue(data, 'account_id');
    if (accountId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingAccountId,
      );
    }
    if (!_isExactOpaqueTargetId(accountId)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.invalidAccountId,
      );
    }
    final roomId = _exactValue(data, 'room_id');
    if (roomId == null) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.missingRoomId,
      );
    }

    if (!_isMatrixRoomId(roomId)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.invalidRoomId,
      );
    }

    final eventId = _exactValue(data, 'event_id');
    final threadRootEventId = _exactValue(data, 'thread_root_event_id');
    final callId = _exactValue(data, 'call_id');
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

    if (eventId != null && !_isMatrixEventId(eventId)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.invalidEventId,
      );
    }
    if (threadRootEventId != null && !_isMatrixEventId(threadRootEventId)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.invalidThreadRootEventId,
      );
    }
    if (callId != null && !_isOpaqueTargetId(callId)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.invalidCallId,
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

  static String? _trimmedValue(Map<String, String?> data, String key) {
    final value = data[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _exactValue(Map<String, String?> data, String key) {
    final value = data[key];
    return value == null || value.isEmpty ? null : value;
  }

  static bool _isMatrixRoomId(String value) =>
      value.startsWith('!') &&
      value.length > 2 &&
      value.contains(':') &&
      !value.contains(RegExp(r'\s'));

  static bool _isMatrixEventId(String value) =>
      value.startsWith(r'$') &&
      value.length > 1 &&
      !value.contains(RegExp(r'\s'));

  static bool _isOpaqueTargetId(String value) =>
      value.isNotEmpty && !value.contains(RegExp(r'\s'));

  static bool _isExactOpaqueTargetId(String value) =>
      value == value.trim() && _isOpaqueTargetId(value);
}

abstract interface class NotificationIngressAccountPort {
  Future<bool> containsAccount(String accountId);
}

typedef NotificationIngressHandler = Future<void> Function(
  NotificationIngressResult result,
);

final class NotificationIngressCoordinator {
  const NotificationIngressCoordinator({
    required this.onAccepted,
    required this.accounts,
    this.parser = const NotificationIngressParser(),
  });

  final NotificationIngressHandler onAccepted;
  final NotificationIngressAccountPort accounts;
  final NotificationIngressParser parser;

  Future<NotificationIngressResult> receive({
    required NotificationIngressTransport transport,
    required Map<String, String?> data,
  }) async {
    final result = parser.parse(transport: transport, data: data);
    if (!result.accepted) return result;

    final account = result.notification!.destination.accountId;
    if (!await accounts.containsAccount(account)) {
      return NotificationIngressResult.rejected(
        transport: transport,
        failure: NotificationIngressFailure.unknownAccount,
      );
    }

    await onAccepted(result);
    return result;
  }
}
