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

  MatrixPresentationSnapshot snapshot({
    int? roomLimit,
    int? timelineEventLimitPerRoom,
  }) {
    assert(roomLimit == null || roomLimit > 0);
    assert(timelineEventLimitPerRoom == null || timelineEventLimitPerRoom > 0);
    final orderedRoomIds = roomLimit == null
        ? roomOrder.value
        : roomOrder.value.take(roomLimit);
    final persistedRoomIds = orderedRoomIds.toSet();
    final preservesCompleteRoomSet =
        roomLimit == null || roomOrder.value.length <= roomLimit;

    return MatrixPresentationSnapshot(
      rooms: <MatrixRoomSummary>[
        for (final roomId in orderedRoomIds) ?_roomSummaries[roomId]?.value,
      ],
      timelines: <String, List<MatrixTimelineEvent>>{
        for (final roomId in persistedRoomIds)
          if (_timelines[roomId]?.value.isNotEmpty ?? false)
            roomId: _recentEvents(
              _timelines[roomId]!.value,
              timelineEventLimitPerRoom,
            ),
      },
      syncCursor: preservesCompleteRoomSet ? lastSyncCursor : null,
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
    _validateSnapshot(snapshot);
    batch(() {
      lastSyncCursor = snapshot.syncCursor;

      final restoredRoomIds = snapshot.rooms
          .map((summary) => summary.roomId)
          .toSet();
      for (final entry in _roomSummaries.entries) {
        if (!restoredRoomIds.contains(entry.key) && entry.value.value != null) {
          entry.value.value = null;
        }
      }
      for (final summary in snapshot.rooms) {
        final summarySignal = roomSummarySignal(summary.roomId);
        if (!_sameSummary(summarySignal.value, summary)) {
          summarySignal.value = summary;
        }
      }

      final restoredTimelineIds = snapshot.timelines.keys.toSet();
      for (final entry in _timelines.entries) {
        if (!restoredTimelineIds.contains(entry.key) &&
            entry.value.value.isNotEmpty) {
          entry.value.value = const <MatrixTimelineEvent>[];
        }
      }
      for (final entry in snapshot.timelines.entries) {
        final timeline = timelineSignal(entry.key);
        final restored = _mergeEvents(
          const <MatrixTimelineEvent>[],
          entry.value,
        );
        if (!_sameTimeline(timeline.value, restored)) {
          timeline.value = restored;
        }
      }
      _refreshRoomOrder();
    });
  }

  bool applyPagination(MatrixPaginationPage page) {
    _validatePaginationPage(page);
    if (page.events.isEmpty) return false;
    final timeline = timelineSignal(page.roomId);
    final merged = _mergeEvents(timeline.value, page.events);
    if (_sameTimeline(timeline.value, merged)) return false;
    timeline.value = merged;
    return true;
  }

  bool updateRoomFavourite(String roomId, bool isFavourite) {
    _requireSafeIdentifier(roomId, 'room id');
    final summarySignal = _roomSummaries[roomId];
    final current = summarySignal?.value;
    if (current == null || current.isFavourite == isFavourite) return false;
    summarySignal!.value = MatrixRoomSummary(
      roomId: current.roomId,
      displayName: current.displayName,
      lastActivity: current.lastActivity,
      streamPosition: current.streamPosition,
      lastEventId: current.lastEventId,
      unreadCount: current.unreadCount,
      highlightCount: current.highlightCount,
      isFavourite: isFavourite,
      isMuted: current.isMuted,
    );
    return true;
  }

  void applySync(MatrixSyncBatch syncBatch) {
    _validateSyncBatch(syncBatch);
    batch(() {
      var roomOrderDirty = false;
      for (final room in syncBatch.rooms) {
        final summary = room.summary;
        if (summary != null) {
          final summarySignal = roomSummarySignal(room.roomId);
          final current = summarySignal.value;
          if (current == null ||
              summary.streamPosition >= current.streamPosition) {
            if (!_sameSummary(current, summary)) {
              roomOrderDirty =
                  roomOrderDirty || _changesRoomOrder(current, summary);
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

      if (syncBatch.commitCursor) {
        lastSyncCursor = syncBatch.cursor;
      }
      if (roomOrderDirty) {
        _refreshRoomOrder();
      }
    });
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

  static void _validateSnapshot(MatrixPresentationSnapshot snapshot) {
    final cursor = snapshot.syncCursor;
    if (cursor != null) {
      _requireSafeIdentifier(cursor, 'snapshot sync cursor');
    }
    final roomIds = <String>{};
    for (final summary in snapshot.rooms) {
      _requireSafeIdentifier(summary.roomId, 'snapshot room id');
      if (!roomIds.add(summary.roomId)) {
        throw ArgumentError(
          'snapshot must not contain duplicate room summaries',
        );
      }
    }
    for (final entry in snapshot.timelines.entries) {
      _requireSafeIdentifier(entry.key, 'snapshot timeline room id');
      if (!roomIds.contains(entry.key)) {
        throw ArgumentError(
          'snapshot timeline must belong to a persisted room',
        );
      }
      _validateRoomScopedEvents(
        ownerRoomId: entry.key,
        events: entry.value,
        argument: snapshot,
        argumentName: 'snapshot',
      );
    }
  }

  static void _validateSyncBatch(MatrixSyncBatch syncBatch) {
    _requireSafeIdentifier(syncBatch.cursor, 'sync cursor');
    for (final room in syncBatch.rooms) {
      _requireSafeIdentifier(room.roomId, 'sync room id');
      final summary = room.summary;
      if (summary != null && summary.roomId != room.roomId) {
        throw ArgumentError.value(
          syncBatch,
          'syncBatch',
          'room summary must match its owning sync room',
        );
      }
      _validateRoomScopedEvents(
        ownerRoomId: room.roomId,
        events: room.timelineEvents,
        argument: syncBatch,
        argumentName: 'syncBatch',
      );
    }
  }

  static void _validatePaginationPage(MatrixPaginationPage page) {
    _requireSafeIdentifier(page.roomId, 'pagination room id');
    _validateRoomScopedEvents(
      ownerRoomId: page.roomId,
      events: page.events,
      argument: page,
      argumentName: 'page',
    );
  }

  static void _validateRoomScopedEvents({
    required String ownerRoomId,
    required List<MatrixTimelineEvent> events,
    required Object argument,
    required String argumentName,
  }) {
    for (final event in events) {
      _requireSafeIdentifier(event.eventId, 'event id');
      _requireSafeIdentifier(event.roomId, 'event room id');
      if (event.roomId != ownerRoomId) {
        throw ArgumentError.value(
          argument,
          argumentName,
          'timeline event must match its owning room',
        );
      }
    }
  }

  static void _requireSafeIdentifier(String value, String name) {
    if (value.isEmpty || value.contains('\u0000')) {
      throw ArgumentError('$name must be non-empty without NUL bytes');
    }
  }

  static List<MatrixTimelineEvent> _recentEvents(
    List<MatrixTimelineEvent> events,
    int? limit,
  ) {
    if (limit == null || events.length <= limit) return events;
    return events.sublist(events.length - limit);
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

  static bool _changesRoomOrder(
    MatrixRoomSummary? current,
    MatrixRoomSummary next,
  ) {
    return current == null ||
        current.lastActivity != next.lastActivity ||
        current.streamPosition != next.streamPosition;
  }

  static bool _sameSummary(MatrixRoomSummary? left, MatrixRoomSummary right) {
    if (left == null) return false;
    return left.roomId == right.roomId &&
        left.displayName == right.displayName &&
        left.lastActivity == right.lastActivity &&
        left.streamPosition == right.streamPosition &&
        left.lastEventId == right.lastEventId &&
        left.unreadCount == right.unreadCount &&
        left.highlightCount == right.highlightCount &&
        left.isFavourite == right.isFavourite &&
        left.isMuted == right.isMuted;
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
          a.senderDisplayName != b.senderDisplayName ||
          a.type != b.type ||
          !_sameJsonValue(a.content, b.content)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameJsonValue(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_sameJsonValue(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index += 1) {
        if (!_sameJsonValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
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
