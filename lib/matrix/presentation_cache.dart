import 'package:kite/matrix/matrix_models.dart';
import 'package:signals/signals.dart';

final class MatrixPresentationCache {
  MatrixPresentationCache({MatrixPresentationSnapshot? initialSnapshot}) {
    if (initialSnapshot != null) {
      restore(initialSnapshot);
    }
  }

  final Signal<List<String>> roomOrder = signal<List<String>>(const <String>[]);
  final Map<String, Signal<MatrixRoomSummary?>> _roomSummaries =
      <String, Signal<MatrixRoomSummary?>>{};
  final Map<String, Signal<List<MatrixTimelineEvent>>> _timelines =
      <String, Signal<List<MatrixTimelineEvent>>>{};

  String? lastSyncCursor;

  MatrixPresentationSnapshot snapshot() {
    return MatrixPresentationSnapshot(
      rooms: <MatrixRoomSummary>[
        for (final roomId in roomOrder.value) ?_roomSummaries[roomId]?.value,
      ],
      timelines: <String, List<MatrixTimelineEvent>>{
        for (final entry in _timelines.entries)
          if (entry.value.value.isNotEmpty) entry.key: entry.value.value,
      },
      syncCursor: lastSyncCursor,
    );
  }

  Signal<MatrixRoomSummary?> roomSummarySignal(String roomId) {
    return _roomSummaries.putIfAbsent(
      roomId,
      () => signal<MatrixRoomSummary?>(null),
    );
  }

  Signal<List<MatrixTimelineEvent>> timelineSignal(String roomId) {
    return _timelines.putIfAbsent(
      roomId,
      () => signal<List<MatrixTimelineEvent>>(const <MatrixTimelineEvent>[]),
    );
  }

  void restore(MatrixPresentationSnapshot snapshot) {
    lastSyncCursor = snapshot.syncCursor;
    for (final summary in snapshot.rooms) {
      roomSummarySignal(summary.roomId).value = summary;
    }
    for (final entry in snapshot.timelines.entries) {
      timelineSignal(entry.key).value = _mergeEvents(
        const <MatrixTimelineEvent>[],
        entry.value,
      );
    }
    _refreshRoomOrder();
  }

  void applySync(MatrixSyncBatch batch) {
    for (final room in batch.rooms) {
      final summary = room.summary;
      if (summary != null) {
        final summarySignal = roomSummarySignal(room.roomId);
        final current = summarySignal.value;
        if (current == null ||
            summary.streamPosition >= current.streamPosition) {
          if (!_sameSummary(current, summary)) {
            summarySignal.value = summary;
          }
        }
      }

      if (room.timelineEvents.isNotEmpty) {
        final timeline = timelineSignal(room.roomId);
        final merged = _mergeEvents(timeline.value, room.timelineEvents);
        if (!_sameTimeline(timeline.value, merged)) {
          timeline.value = merged;
        }
      }
    }

    lastSyncCursor = batch.cursor;
    _refreshRoomOrder();
  }

  void _refreshRoomOrder() {
    final next =
        _roomSummaries.entries
            .where((entry) => entry.value.value != null)
            .map((entry) => entry.value.value!)
            .toList(growable: false)
          ..sort((left, right) {
            final activity = right.lastActivity.compareTo(left.lastActivity);
            if (activity != 0) return activity;
            final position = right.streamPosition.compareTo(
              left.streamPosition,
            );
            if (position != 0) return position;
            return left.roomId.compareTo(right.roomId);
          });
    final ids = List<String>.unmodifiable(next.map((room) => room.roomId));
    if (!_sameStrings(roomOrder.value, ids)) {
      roomOrder.value = ids;
    }
  }

  static List<MatrixTimelineEvent> _mergeEvents(
    List<MatrixTimelineEvent> current,
    List<MatrixTimelineEvent> incoming,
  ) {
    final byId = <String, MatrixTimelineEvent>{
      for (final event in current) event.eventId: event,
    };

    for (final event in incoming) {
      final existing = byId[event.eventId];
      if (existing == null || _compareEventFreshness(event, existing) >= 0) {
        byId[event.eventId] = event;
      }
    }

    final merged = byId.values.toList(growable: false)
      ..sort((left, right) {
        final position = left.streamPosition.compareTo(right.streamPosition);
        if (position != 0) return position;
        final timestamp = left.originServerTimestamp.compareTo(
          right.originServerTimestamp,
        );
        if (timestamp != 0) return timestamp;
        return left.eventId.compareTo(right.eventId);
      });
    return List<MatrixTimelineEvent>.unmodifiable(merged);
  }

  static int _compareEventFreshness(
    MatrixTimelineEvent left,
    MatrixTimelineEvent right,
  ) {
    final position = left.streamPosition.compareTo(right.streamPosition);
    if (position != 0) return position;
    return left.originServerTimestamp.compareTo(right.originServerTimestamp);
  }

  static bool _sameSummary(MatrixRoomSummary? left, MatrixRoomSummary right) {
    if (left == null) return false;
    return left.roomId == right.roomId &&
        left.displayName == right.displayName &&
        left.lastActivity == right.lastActivity &&
        left.streamPosition == right.streamPosition &&
        left.lastEventId == right.lastEventId &&
        left.unreadCount == right.unreadCount;
  }

  static bool _sameTimeline(
    List<MatrixTimelineEvent> left,
    List<MatrixTimelineEvent> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      final a = left[index];
      final b = right[index];
      if (a.eventId != b.eventId ||
          a.streamPosition != b.streamPosition ||
          a.originServerTimestamp != b.originServerTimestamp ||
          a.roomId != b.roomId ||
          a.senderId != b.senderId ||
          a.type != b.type ||
          a.content.toString() != b.content.toString()) {
        return false;
      }
    }
    return true;
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
