import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';

final class PlatformNotificationDeliveryPort
    implements NotificationDeliveryPort {
  const PlatformNotificationDeliveryPort();

  static const MethodChannel _channel = MethodChannel(
    'nz.presley.kite/notifications',
  );

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  @override
  Future<void> show(KiteNotificationPresentation presentation) async {
    if (!isSupported) return;
    final destination = presentation.notification.destination;
    await _channel.invokeMethod<void>('show', <String, Object?>{
      'routingId': presentation.notification.routingId,
      'kind': presentation.notification.kind.name,
      'title': presentation.title,
      'body': presentation.body,
      'groupKey': presentation.groupKey,
      'accountId': destination.accountId,
      'roomId': destination.roomId,
      'eventId': destination.eventId,
      'threadRootEventId': destination.threadRootEventId,
      'callId': destination.callId,
      'contentsHidden': presentation.contentsHidden,
    });
  }

  @override
  Future<void> cancel(String notificationId) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancel', <String, Object?>{
      'routingId': notificationId,
    });
  }

  @override
  Future<void> showSummary(KiteNotificationSummary summary) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('showSummary', <String, Object?>{
      'groupKey': summary.groupKey,
      'accountId': summary.accountId,
      'roomId': summary.roomId,
      'count': summary.count,
      'contentsHidden': summary.contentsHidden,
    });
  }

  @override
  Future<void> cancelSummary(String groupKey) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancelSummary', <String, Object?>{
      'groupKey': groupKey,
    });
  }
}

final class ProductionNotificationRuntime {
  ProductionNotificationRuntime({
    PlatformNotificationDeliveryPort delivery =
        const PlatformNotificationDeliveryPort(),
  }) : _delivery = delivery {
    final deliveryCoordinator = NotificationDeliveryCoordinator(
      privacy: const _VisibleNotificationPrivacy(),
      delivery: delivery,
    );
    _dispatch = NotificationDispatchCoordinator(
      notifications: _registrations,
      delivery: deliveryCoordinator,
    );
  }

  final PlatformNotificationDeliveryPort _delivery;
  final _ProductionNotificationRegistrations _registrations =
      _ProductionNotificationRegistrations();
  late final NotificationDispatchCoordinator _dispatch;
  final Set<String> _deliveredEventIds = <String>{};

  static const int _rememberedEventLimit = 512;

  bool get isSupported => _delivery.isSupported;

  Future<bool> requestPermission() => _delivery.requestPermission();

  Future<void> handleSyncBatch({
    required String accountId,
    required MatrixSyncBatch batch,
    required bool isInitialSync,
    required MatrixAppActivity activity,
  }) async {
    if (!isSupported ||
        isInitialSync ||
        activity != MatrixAppActivity.background) {
      return;
    }

    for (final invite in batch.invites) {
      await _dispatch.dispatch(
        MatrixNotificationEvent(
          id: 'invite:${invite.roomId}',
          kind: MatrixNotificationEventKind.invite,
          accountId: accountId,
          roomId: invite.roomId,
          title: invite.roomName.trim().isEmpty
              ? 'Room invitation'
              : invite.roomName,
          body: '${invite.inviterDisplayName} invited you',
        ),
      );
    }

    for (final room in batch.rooms) {
      if (room.summary?.isMuted == true) continue;
      for (final event in room.timelineEvents) {
        if (event.senderId == accountId ||
            event.redacted ||
            event.type != 'm.room.message' ||
            !_rememberEvent(event.eventId)) {
          continue;
        }

        final threadRootEventId = _threadRootEventId(event);
        final kind = threadRootEventId != null
            ? MatrixNotificationEventKind.thread
            : _mentionsAccount(event, accountId)
            ? MatrixNotificationEventKind.mention
            : MatrixNotificationEventKind.message;
        await _dispatch.dispatch(
          MatrixNotificationEvent(
            id: event.eventId,
            kind: kind,
            accountId: accountId,
            roomId: room.roomId,
            title: _titleFor(room, event),
            body: _bodyFor(event),
            eventId: event.eventId,
            threadRootEventId: threadRootEventId,
          ),
        );
      }
    }
  }

  bool _rememberEvent(String eventId) {
    if (_deliveredEventIds.contains(eventId)) return false;
    _deliveredEventIds.add(eventId);
    if (_deliveredEventIds.length > _rememberedEventLimit) {
      _deliveredEventIds.remove(_deliveredEventIds.first);
    }
    return true;
  }

  String _titleFor(MatrixRoomDelta room, MatrixTimelineEvent event) {
    final roomName = room.summary?.displayName.trim();
    if (roomName != null && roomName.isNotEmpty) return roomName;
    final senderName = event.senderDisplayName?.trim();
    if (senderName != null && senderName.isNotEmpty) return senderName;
    return event.senderId;
  }

  String _bodyFor(MatrixTimelineEvent event) {
    final body = event.content['body'];
    if (body is String && body.trim().isNotEmpty) return body.trim();
    return switch (event.content['msgtype']) {
      'm.image' => 'Image',
      'm.video' => 'Video',
      'm.audio' => 'Audio',
      'm.file' => 'File',
      'm.location' => 'Location',
      _ => 'New message',
    };
  }

  bool _mentionsAccount(MatrixTimelineEvent event, String accountId) {
    final mentions = event.content['m.mentions'];
    if (mentions is! Map) return false;
    final userIds = mentions['user_ids'];
    return userIds is List && userIds.contains(accountId);
  }

  String? _threadRootEventId(MatrixTimelineEvent event) {
    final relatesTo = event.content['m.relates_to'];
    if (relatesTo is! Map || relatesTo['rel_type'] != 'm.thread') return null;
    final eventId = relatesTo['event_id'];
    if (eventId is! String ||
        !eventId.startsWith(r'$') ||
        eventId.length <= 1 ||
        eventId.contains(RegExp(r'\s'))) {
      return null;
    }
    return eventId;
  }
}

final class _VisibleNotificationPrivacy implements NotificationPrivacyPort {
  const _VisibleNotificationPrivacy();

  @override
  bool get hideNotificationContents => false;
}

final class _ProductionNotificationRegistrations
    implements NotificationRegistrationPort {
  final Map<String, KiteNotification> _notifications =
      <String, KiteNotification>{};

  @override
  void upsertNotification(KiteNotification notification) {
    _notifications[notification.routingId] = notification;
  }
}
