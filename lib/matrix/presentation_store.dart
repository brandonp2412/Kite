import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:kite/matrix/matrix_models.dart';

abstract interface class MatrixPresentationStore {
  Future<MatrixPresentationSnapshot?> load(String accountId);

  Future<void> save(String accountId, MatrixPresentationSnapshot snapshot);

  Future<void> clear(String accountId);
}

final class FileMatrixPresentationStore implements MatrixPresentationStore {
  FileMatrixPresentationStore(this.rootDirectory);

  static const int _schemaVersion = 1;

  final Directory rootDirectory;

  @override
  Future<MatrixPresentationSnapshot?> load(String accountId) async {
    final file = _fileFor(accountId);
    if (!await file.exists()) return null;

    final contents = await file.readAsString();
    if (contents.trim().isEmpty) return null;

    try {
      final decoded = await Isolate.run<Object?>(() => jsonDecode(contents));
      if (decoded is! Map<String, dynamic>) return null;
      return _decodeSnapshot(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(
    String accountId,
    MatrixPresentationSnapshot snapshot,
  ) async {
    final file = _fileFor(accountId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final document = _encodeSnapshot(snapshot);
    final payload = await Isolate.run<String>(() => jsonEncode(document));

    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear(String accountId) async {
    final file = _fileFor(accountId);
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    if (await file.exists()) await file.delete();
  }

  File _fileFor(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    final encoded = Uri.encodeComponent(normalized);
    return File('${rootDirectory.path}/$encoded/presentation.json');
  }

  static Map<String, Object?> _encodeSnapshot(
    MatrixPresentationSnapshot snapshot,
  ) {
    return <String, Object?>{
      'version': _schemaVersion,
      if (snapshot.syncCursor != null) 'syncCursor': snapshot.syncCursor,
      'rooms': <Object?>[
        for (final room in snapshot.rooms)
          <String, Object?>{
            'roomId': room.roomId,
            'displayName': room.displayName,
            'lastActivityMs': room.lastActivity.millisecondsSinceEpoch,
            'streamPosition': room.streamPosition,
            if (room.lastEventId != null) 'lastEventId': room.lastEventId,
            'unreadCount': room.unreadCount,
          },
      ],
      'timelines': <String, Object?>{
        for (final entry in snapshot.timelines.entries)
          entry.key: <Object?>[
            for (final event in entry.value)
              <String, Object?>{
                'eventId': event.eventId,
                'roomId': event.roomId,
                'senderId': event.senderId,
                'type': event.type,
                'originServerTimestampMs':
                    event.originServerTimestamp.millisecondsSinceEpoch,
                'streamPosition': event.streamPosition,
                'content': event.content,
              },
          ],
      },
    };
  }

  static MatrixPresentationSnapshot? _decodeSnapshot(
    Map<String, dynamic> document,
  ) {
    if (document['version'] != _schemaVersion) return null;
    final syncCursor = document['syncCursor'];
    if (syncCursor != null && syncCursor is! String) return null;
    final rawRooms = document['rooms'];
    final rawTimelines = document['timelines'];
    if (rawRooms is! List || rawTimelines is! Map) return null;

    final rooms = <MatrixRoomSummary>[];
    for (final rawRoom in rawRooms) {
      if (rawRoom is! Map) return null;
      final room = _decodeRoom(Map<String, dynamic>.from(rawRoom));
      if (room == null) return null;
      rooms.add(room);
    }

    final timelines = <String, List<MatrixTimelineEvent>>{};
    for (final entry in rawTimelines.entries) {
      if (entry.key is! String || entry.value is! List) return null;
      final events = <MatrixTimelineEvent>[];
      for (final rawEvent in entry.value as List) {
        if (rawEvent is! Map) return null;
        final event = _decodeEvent(Map<String, dynamic>.from(rawEvent));
        if (event == null) return null;
        events.add(event);
      }
      timelines[entry.key as String] = events;
    }

    return MatrixPresentationSnapshot(
      rooms: rooms,
      timelines: timelines,
      syncCursor: syncCursor as String?,
    );
  }

  static MatrixRoomSummary? _decodeRoom(Map<String, dynamic> value) {
    final roomId = value['roomId'];
    final displayName = value['displayName'];
    final lastActivityMs = value['lastActivityMs'];
    final streamPosition = value['streamPosition'];
    final lastEventId = value['lastEventId'];
    final unreadCount = value['unreadCount'];
    if (roomId is! String ||
        roomId.isEmpty ||
        displayName is! String ||
        lastActivityMs is! int ||
        streamPosition is! int ||
        (lastEventId != null && lastEventId is! String) ||
        unreadCount is! int) {
      return null;
    }
    return MatrixRoomSummary(
      roomId: roomId,
      displayName: displayName,
      lastActivity: DateTime.fromMillisecondsSinceEpoch(
        lastActivityMs,
        isUtc: true,
      ),
      streamPosition: streamPosition,
      lastEventId: lastEventId as String?,
      unreadCount: unreadCount,
    );
  }

  static MatrixTimelineEvent? _decodeEvent(Map<String, dynamic> value) {
    final eventId = value['eventId'];
    final roomId = value['roomId'];
    final senderId = value['senderId'];
    final type = value['type'];
    final timestampMs = value['originServerTimestampMs'];
    final streamPosition = value['streamPosition'];
    final content = value['content'];
    if (eventId is! String ||
        eventId.isEmpty ||
        roomId is! String ||
        roomId.isEmpty ||
        senderId is! String ||
        senderId.isEmpty ||
        type is! String ||
        type.isEmpty ||
        timestampMs is! int ||
        streamPosition is! int ||
        content is! Map) {
      return null;
    }
    return MatrixTimelineEvent(
      eventId: eventId,
      roomId: roomId,
      senderId: senderId,
      type: type,
      originServerTimestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampMs,
        isUtc: true,
      ),
      streamPosition: streamPosition,
      content: Map<String, Object?>.from(content),
    );
  }
}
