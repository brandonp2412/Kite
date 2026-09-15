import 'dart:convert';

import 'package:kite/matrix/matrix_models.dart';

final class MatrixRustSyncDecodeResult {
  const MatrixRustSyncDecodeResult({required this.batch});

  final MatrixSyncBatch batch;
}

final class MatrixRustPaginationDecodeResult {
  const MatrixRustPaginationDecodeResult({
    required this.roomId,
    required this.events,
    required this.reachedStart,
  });

  final String roomId;
  final List<MatrixTimelineEvent> events;
  final bool reachedStart;
}

final class MatrixRustSyncCodec {
  MatrixRustSyncDecodeResult decodeSync(String payload) {
    final root = _asMap(jsonDecode(payload), 'sync payload');
    final cursor = _requiredString(root, 'cursor');
    final rooms = <MatrixRoomDelta>[];

    for (final rawRoom in _asList(root['rooms'], 'rooms')) {
      final room = _asMap(rawRoom, 'room');
      final roomId = _requiredString(room, 'roomId');
      final events = _decodeEvents(roomId, room['events']);
      final lastEvent = events.isEmpty ? null : events.last;
      final latestEventTimestamp =
          _optionalNonNegativeInt(room['latestEventTimestamp']) ??
          lastEvent?.originServerTimestamp.millisecondsSinceEpoch ??
          0;
      rooms.add(
        MatrixRoomDelta(
          roomId: roomId,
          summary: MatrixRoomSummary(
            roomId: roomId,
            displayName: _optionalString(room['displayName']) ?? roomId,
            lastActivity: DateTime.fromMillisecondsSinceEpoch(
              latestEventTimestamp,
              isUtc: true,
            ),
            streamPosition: latestEventTimestamp,
            lastEventId:
                _optionalString(room['latestEventId']) ?? lastEvent?.eventId,
            unreadCount: _optionalNonNegativeInt(room['unreadCount']) ?? 0,
          ),
          timelineEvents: events,
        ),
      );
    }

    return MatrixRustSyncDecodeResult(
      batch: MatrixSyncBatch(cursor: cursor, rooms: rooms),
    );
  }

  MatrixRustPaginationDecodeResult decodePagination(String payload) {
    final root = _asMap(jsonDecode(payload), 'pagination payload');
    final roomId = _requiredString(root, 'roomId');
    return MatrixRustPaginationDecodeResult(
      roomId: roomId,
      events: _decodeBackPaginationEvents(roomId, root['events']),
      reachedStart: _requiredBool(root, 'reachedStart'),
    );
  }

  List<MatrixTimelineEvent> _decodeEvents(String roomId, Object? value) {
    return List<MatrixTimelineEvent>.unmodifiable(
      _asList(
        value,
        'events',
      ).map((rawEvent) => _decodeEvent(roomId, rawEvent)),
    );
  }

  List<MatrixTimelineEvent> _decodeBackPaginationEvents(
    String roomId,
    Object? value,
  ) {
    return List<MatrixTimelineEvent>.unmodifiable(
      _asList(
        value,
        'events',
      ).reversed.map((rawEvent) => _decodeEvent(roomId, rawEvent)),
    );
  }

  MatrixTimelineEvent _decodeEvent(String roomId, Object? rawEvent) {
    final event = _asMap(rawEvent, 'timeline event');
    final timestamp = _requiredNonNegativeInt(event, 'origin_server_ts');
    return MatrixTimelineEvent(
      eventId: _requiredString(event, 'event_id'),
      roomId: roomId,
      senderId: _requiredString(event, 'sender'),
      type: _requiredString(event, 'type'),
      originServerTimestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ),
      streamPosition: timestamp,
      content: Map<String, Object?>.unmodifiable(
        _asMap(event['content'], 'event content'),
      ),
    );
  }

  static Map<String, Object?> _asMap(Object? value, String name) {
    if (value is! Map) {
      throw FormatException('$name must be a JSON object');
    }
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static List<Object?> _asList(Object? value, String name) {
    if (value is! List) {
      throw FormatException('$name must be a JSON array');
    }
    return List<Object?>.unmodifiable(value);
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = _optionalString(map[key]);
    if (value == null || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  static String? _optionalString(Object? value) {
    return value is String ? value : null;
  }

  static bool _requiredBool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) {
      throw FormatException('$key must be a boolean');
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, Object?> map, String key) {
    final value = _optionalNonNegativeInt(map[key]);
    if (value == null) {
      throw FormatException('$key must be a non-negative integer');
    }
    return value;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value is int && value >= 0) return value;
    return null;
  }
}
