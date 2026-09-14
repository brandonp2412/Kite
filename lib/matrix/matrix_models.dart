import 'dart:collection';

final class MatrixTimelineEvent {
  MatrixTimelineEvent({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.originServerTimestamp,
    required this.streamPosition,
    Map<String, Object?> content = const <String, Object?>{},
  }) : content = UnmodifiableMapView<String, Object?>(content);

  final String eventId;
  final String roomId;
  final String senderId;
  final String type;
  final DateTime originServerTimestamp;
  final int streamPosition;
  final Map<String, Object?> content;
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
  const MatrixSyncBatch({required this.cursor, required this.rooms});

  final String cursor;
  final List<MatrixRoomDelta> rooms;
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
