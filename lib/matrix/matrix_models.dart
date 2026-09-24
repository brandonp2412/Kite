import 'dart:collection';

final class MatrixTimelineEvent {
  MatrixTimelineEvent({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    this.senderDisplayName,
    this.senderAvatarUrl,
    required this.type,
    required this.originServerTimestamp,
    required this.streamPosition,
    this.transactionId,
    this.redactsEventId,
    this.redacted = false,
    Map<String, Object?> content = const <String, Object?>{},
  }) : content = freezeMatrixJsonMap(content);

  final String eventId;
  final String roomId;
  final String senderId;
  final String? senderDisplayName;
  final String? senderAvatarUrl;
  final String type;
  final DateTime originServerTimestamp;
  final int streamPosition;
  final String? transactionId;
  final String? redactsEventId;
  final bool redacted;
  final Map<String, Object?> content;

  MatrixTimelineEvent copyWith({
    bool? redacted,
    Map<String, Object?>? content,
  }) {
    return MatrixTimelineEvent(
      eventId: eventId,
      roomId: roomId,
      senderId: senderId,
      senderDisplayName: senderDisplayName,
      senderAvatarUrl: senderAvatarUrl,
      type: type,
      originServerTimestamp: originServerTimestamp,
      streamPosition: streamPosition,
      transactionId: transactionId,
      redactsEventId: redactsEventId,
      redacted: redacted ?? this.redacted,
      content: content ?? this.content,
    );
  }
}

Map<String, Object?> freezeMatrixJsonMap(Map<String, Object?> value) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in value.entries) entry.key: _freezeJsonValue(entry.value),
  });
}

Object? _freezeJsonValue(Object? value) {
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          value,
          'content',
          'Matrix JSON object keys must be strings',
        );
      }
      frozen[key] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  throw ArgumentError.value(
    value,
    'content',
    'Matrix content must contain only finite JSON values',
  );
}

final class MatrixRoomSummary {
  const MatrixRoomSummary({
    required this.roomId,
    required this.displayName,
    required this.lastActivity,
    required this.streamPosition,
    this.lastEventId,
    this.fullyReadEventId,
    this.avatarUrl,
    this.unreadCount = 0,
    this.unreadMessageCount = 0,
    this.highlightCount = 0,
    this.hasActiveCall = false,
    this.isFavourite = false,
    this.isMuted = false,
    this.isDirect = false,
    this.isSpace = false,
    this.memberCount = 0,
    this.topic,
    this.childRoomIds = const <String>[],
  });

  final String roomId;
  final String displayName;
  final DateTime lastActivity;
  final int streamPosition;
  final String? lastEventId;
  final String? fullyReadEventId;
  final String? avatarUrl;
  final int unreadCount;
  final int unreadMessageCount;
  final int highlightCount;
  final bool hasActiveCall;
  final bool isFavourite;
  final bool isMuted;
  final bool isDirect;
  final bool isSpace;
  final int memberCount;
  final String? topic;
  final List<String> childRoomIds;
}

final class MatrixRoomInvite {
  const MatrixRoomInvite({
    required this.roomId,
    required this.roomName,
    required this.inviterId,
    required this.inviterDisplayName,
    required this.memberCount,
    this.description,
  });

  final String roomId;
  final String roomName;
  final String inviterId;
  final String inviterDisplayName;
  final int memberCount;
  final String? description;
}

final class MatrixReadReceipt {
  const MatrixReadReceipt({
    required this.eventId,
    required this.userId,
    required this.displayName,
  });

  final String eventId;
  final String userId;
  final String displayName;
}

final class MatrixRoomDelta {
  const MatrixRoomDelta({
    required this.roomId,
    this.summary,
    this.timelineEvents = const <MatrixTimelineEvent>[],
    this.typingUsers,
    this.readReceipts,
  });

  final String roomId;
  final MatrixRoomSummary? summary;
  final List<MatrixTimelineEvent> timelineEvents;
  final List<String>? typingUsers;
  final List<MatrixReadReceipt>? readReceipts;
}

final class MatrixSyncBatch {
  const MatrixSyncBatch({
    required this.cursor,
    required this.rooms,
    this.invites = const <MatrixRoomInvite>[],
    this.removedInviteRoomIds = const <String>[],
    this.removedRoomIds = const <String>[],
    this.replaceInvites = false,
    this.commitCursor = true,
  });

  final String cursor;
  final List<MatrixRoomDelta> rooms;
  final List<MatrixRoomInvite> invites;
  final List<String> removedInviteRoomIds;
  final List<String> removedRoomIds;
  final bool replaceInvites;
  final bool commitCursor;
}

final class MatrixPaginationPage {
  const MatrixPaginationPage({
    required this.roomId,
    required this.events,
    required this.reachedStart,
  });

  final String roomId;
  final List<MatrixTimelineEvent> events;
  final bool reachedStart;
}

final class MatrixPresentationSnapshot {
  MatrixPresentationSnapshot({
    required List<MatrixRoomSummary> rooms,
    List<MatrixRoomInvite> invites = const <MatrixRoomInvite>[],
    Map<String, List<MatrixTimelineEvent>> timelines =
        const <String, List<MatrixTimelineEvent>>{},
    this.syncCursor,
  }) : rooms = List<MatrixRoomSummary>.unmodifiable(rooms),
       invites = List<MatrixRoomInvite>.unmodifiable(invites),
       timelines = UnmodifiableMapView<String, List<MatrixTimelineEvent>>(
         <String, List<MatrixTimelineEvent>>{
           for (final entry in timelines.entries)
             entry.key: List<MatrixTimelineEvent>.unmodifiable(entry.value),
         },
       );

  final List<MatrixRoomSummary> rooms;
  final List<MatrixRoomInvite> invites;
  final Map<String, List<MatrixTimelineEvent>> timelines;
  final String? syncCursor;
}
