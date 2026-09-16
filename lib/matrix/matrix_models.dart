import 'dart:collection';

final class MatrixTimelineEvent {
  MatrixTimelineEvent({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.originServerTimestamp,
    required this.streamPosition,
    this.transactionId,
    Map<String, Object?> content = const <String, Object?>{},
  }) : content = freezeMatrixJsonMap(content);

  final String eventId;
  final String roomId;
  final String senderId;
  final String type;
  final DateTime originServerTimestamp;
  final int streamPosition;
  final String? transactionId;
  final Map<String, Object?> content;
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
    this.unreadCount = 0,
  });

  final String roomId;
  final String displayName;
  final DateTime lastActivity;
  final int streamPosition;
  final String? lastEventId;
  final int unreadCount;
}

final class MatrixRoomDelta {
  const MatrixRoomDelta({
    required this.roomId,
    this.summary,
    this.timelineEvents = const <MatrixTimelineEvent>[],
  });

  final String roomId;
  final MatrixRoomSummary? summary;
  final List<MatrixTimelineEvent> timelineEvents;
}

final class MatrixSyncBatch {
  const MatrixSyncBatch({
    required this.cursor,
    required this.rooms,
    this.commitCursor = true,
  });

  final String cursor;
  final List<MatrixRoomDelta> rooms;
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
    Map<String, List<MatrixTimelineEvent>> timelines =
        const <String, List<MatrixTimelineEvent>>{},
    this.syncCursor,
  }) : rooms = List<MatrixRoomSummary>.unmodifiable(rooms),
       timelines = UnmodifiableMapView<String, List<MatrixTimelineEvent>>(
         <String, List<MatrixTimelineEvent>>{
           for (final entry in timelines.entries)
             entry.key: List<MatrixTimelineEvent>.unmodifiable(entry.value),
         },
       );

  final List<MatrixRoomSummary> rooms;
  final Map<String, List<MatrixTimelineEvent>> timelines;
  final String? syncCursor;
}
