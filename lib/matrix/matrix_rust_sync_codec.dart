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
            fullyReadEventId: _optionalIdentifier(
              room['fullyReadEventId'],
              'fullyReadEventId',
            ),
            avatarUrl: _optionalString(room['avatarUrl']),
            unreadCount: _optionalNonNegativeInt(room['unreadCount']) ?? 0,
            unreadMessageCount:
                _optionalNonNegativeInt(room['unreadMessageCount']) ?? 0,
            highlightCount:
                _optionalNonNegativeInt(room['highlightCount']) ?? 0,
            hasActiveCall: _optionalBool(room['hasActiveCall']) ?? false,
            isFavourite: _optionalBool(room['isFavourite']) ?? false,
            isMuted: _optionalBool(room['isMuted']) ?? false,
            isDirect: _optionalBool(room['isDirect']) ?? false,
          ),
          timelineEvents: events,
          typingUsers: _optionalStringList(room['typingUsers'], 'typingUsers'),
          readReceipts: _decodeReadReceipts(room['readReceipts']),
        ),
      );
    }

    final invites = <MatrixRoomInvite>[];
    for (final rawInvite in _asList(
      root['invites'] ?? const <Object?>[],
      'invites',
    )) {
      final invite = _asMap(rawInvite, 'invite');
      final roomId = _requiredIdentifier(invite, 'roomId');
      final inviterId = _requiredIdentifier(invite, 'inviterId');
      final roomName = _optionalDisplayName(invite['roomName']) ?? roomId;
      final inviterDisplayName =
          _optionalDisplayName(invite['inviterDisplayName']) ?? inviterId;
      final description = _optionalDisplayName(invite['description']);
      invites.add(
        MatrixRoomInvite(
          roomId: roomId,
          roomName: roomName,
          inviterId: inviterId,
          inviterDisplayName: inviterDisplayName,
          memberCount: _optionalNonNegativeInt(invite['memberCount']) ?? 0,
          description: description,
        ),
      );
    }
    invites.sort((left, right) {
      final name = left.roomName.compareTo(right.roomName);
      if (name != 0) return name;
      return left.roomId.compareTo(right.roomId);
    });

    final removedInviteRoomIds = <String>[
      for (final value in _asList(
        root['removedInviteRoomIds'] ?? const <Object?>[],
        'removedInviteRoomIds',
      ))
        _requiredIdentifier(<String, Object?>{'roomId': value}, 'roomId'),
    ];
    final removedRoomIds = <String>[
      for (final value in _asList(
        root['removedRoomIds'] ?? const <Object?>[],
        'removedRoomIds',
      ))
        _requiredIdentifier(<String, Object?>{'roomId': value}, 'roomId'),
    ];

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
        invites: List<MatrixRoomInvite>.unmodifiable(invites),
        removedInviteRoomIds: List<String>.unmodifiable(removedInviteRoomIds),
        removedRoomIds: List<String>.unmodifiable(removedRoomIds),
        replaceInvites: _optionalBool(root['replaceInvites']) ?? false,
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

  List<MatrixReadReceipt>? _decodeReadReceipts(Object? value) {
    if (value == null) return null;
    final receipts = <MatrixReadReceipt>[];
    for (final rawReceipt in _asList(value, 'readReceipts')) {
      final receipt = _asMap(rawReceipt, 'read receipt');
      final userId = _requiredIdentifier(receipt, 'userId');
      receipts.add(
        MatrixReadReceipt(
          eventId: _requiredIdentifier(receipt, 'eventId'),
          userId: userId,
          displayName: _optionalDisplayName(receipt['displayName']) ?? userId,
        ),
      );
    }
    return List<MatrixReadReceipt>.unmodifiable(receipts);
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
    final redactsEventId = _optionalIdentifier(event['redacts'], 'redacts');
    final redacted = unsigned is Map && unsigned['redacted_because'] is Map;
    return MatrixTimelineEvent(
      eventId: _requiredIdentifier(event, 'event_id'),
      roomId: roomId,
      senderId: _requiredIdentifier(event, 'sender'),
      senderDisplayName: _optionalDisplayName(event['sender_display_name']),
      senderAvatarUrl: _optionalString(event['sender_avatar_url']),
      type: _requiredIdentifier(event, 'type'),
      originServerTimestamp: _dateTimeFromMilliseconds(
        timestamp,
        'origin_server_ts',
      ),
      streamPosition: timestamp,
      transactionId: transactionId,
      redactsEventId: redactsEventId,
      redacted: redacted,
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

  static List<String>? _optionalStringList(Object? value, String name) {
    if (value == null) return null;
    final rawValues = _asList(value, name);
    final values = <String>[];
    for (final rawValue in rawValues) {
      final item = _optionalDisplayName(rawValue);
      if (item == null) {
        throw FormatException(
          '$name must contain non-empty strings without NUL bytes',
        );
      }
      values.add(item);
    }
    return List<String>.unmodifiable(values);
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
