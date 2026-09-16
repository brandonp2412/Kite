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
    if (cursor.contains('\u0000')) {
      throw const FormatException('cursor must not contain NUL bytes');
    }
    final rooms = <MatrixRoomDelta>[];

    for (final rawRoom in _asList(root['rooms'], 'rooms')) {
      final room = _asMap(rawRoom, 'room');
      final roomId = _requiredIdentifier(room, 'roomId');
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
            lastActivity: _dateTimeFromMilliseconds(
              latestEventTimestamp,
              'latestEventTimestamp',
            ),
            streamPosition: latestEventTimestamp,
            lastEventId:
                _optionalIdentifier(room['latestEventId'], 'latestEventId') ??
                lastEvent?.eventId,
            unreadCount: _optionalNonNegativeInt(room['unreadCount']) ?? 0,
            highlightCount:
                _optionalNonNegativeInt(room['highlightCount']) ?? 0,
            isFavourite: _optionalBool(room['isFavourite']) ?? false,
          ),
          timelineEvents: events,
        ),
      );
    }

    rooms.sort((left, right) {
      final leftSummary = left.summary!;
      final rightSummary = right.summary!;
      final activity = rightSummary.lastActivity.compareTo(
        leftSummary.lastActivity,
      );
      if (activity != 0) return activity;
      final position = rightSummary.streamPosition.compareTo(
        leftSummary.streamPosition,
      );
      if (position != 0) return position;
      return left.roomId.compareTo(right.roomId);
    });

    return MatrixRustSyncDecodeResult(
      batch: MatrixSyncBatch(
        cursor: cursor,
        rooms: List<MatrixRoomDelta>.unmodifiable(rooms),
      ),
    );
  }

  MatrixRustPaginationDecodeResult decodePagination(String payload) {
    final root = _asMap(jsonDecode(payload), 'pagination payload');
    final roomId = _requiredIdentifier(root, 'roomId');
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
    final unsigned = event['unsigned'];
    final transactionId = unsigned is Map
        ? _optionalIdentifier(
            unsigned['transaction_id'],
            'unsigned.transaction_id',
          )
        : null;
    return MatrixTimelineEvent(
      eventId: _requiredIdentifier(event, 'event_id'),
      roomId: roomId,
      senderId: _requiredIdentifier(event, 'sender'),
      senderDisplayName: _optionalDisplayName(event['sender_display_name']),
      type: _requiredIdentifier(event, 'type'),
      originServerTimestamp: _dateTimeFromMilliseconds(
        timestamp,
        'origin_server_ts',
      ),
      streamPosition: timestamp,
      transactionId: transactionId,
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

  static String? _optionalDisplayName(Object? value) {
    final displayName = _optionalString(value)?.trim();
    if (displayName == null ||
        displayName.isEmpty ||
        displayName.contains('\u0000')) {
      return null;
    }
    return displayName;
  }

  static String _requiredIdentifier(Map<String, Object?> map, String key) {
    final value = _requiredString(map, key);
    if (value.contains('\u0000')) {
      throw FormatException('$key must not contain NUL bytes');
    }
    return value;
  }

  static String? _optionalIdentifier(Object? value, String key) {
    final identifier = _optionalString(value);
    if (identifier == null) return null;
    if (identifier.isEmpty || identifier.contains('\u0000')) {
      throw FormatException(
        '$key must be a non-empty string without NUL bytes',
      );
    }
    return identifier;
  }

  static bool _requiredBool(Map<String, Object?> map, String key) {
    final value = _optionalBool(map[key]);
    if (value == null) {
      throw FormatException('$key must be a boolean');
    }
    return value;
  }

  static bool? _optionalBool(Object? value) => value is bool ? value : null;

  static DateTime _dateTimeFromMilliseconds(int value, String name) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    } on RangeError {
      throw FormatException('$name must be a supported epoch timestamp');
    }
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
