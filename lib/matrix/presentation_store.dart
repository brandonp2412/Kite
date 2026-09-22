import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/recoverable_file.dart';

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
    final contents = await RecoverableFile(_fileFor(accountId))
        .readCandidates();
    if (contents.isEmpty) return null;

    return Isolate.run<MatrixPresentationSnapshot?>(() {
      for (final candidate in contents) {
        if (candidate.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(candidate);
          if (decoded is! Map<String, dynamic>) continue;
          final snapshot = _decodeSnapshot(decoded);
          if (snapshot != null) return snapshot;
        } on FormatException {
          continue;
        } on RangeError {
          continue;
        }
      }
      return null;
    });
  }

  @override
  Future<void> save(
    String accountId,
    MatrixPresentationSnapshot snapshot,
  ) async {
    final payload = await Isolate.run<String>(
      () => jsonEncode(_encodeSnapshot(snapshot)),
    );
    await RecoverableFile(_fileFor(accountId)).replaceWithString(payload);
  }

  @override
  Future<void> clear(String accountId) {
    return RecoverableFile(_fileFor(accountId)).clear();
  }

  File _fileFor(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must contain a non-empty account id without NUL bytes',
      );
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
      'invites': <Object?>[
        for (final invite in snapshot.invites)
          <String, Object?>{
            'roomId': invite.roomId,
            'roomName': invite.roomName,
            'inviterId': invite.inviterId,
            'inviterDisplayName': invite.inviterDisplayName,
            'memberCount': invite.memberCount,
            if (invite.description != null) 'description': invite.description,
          },
      ],
      'rooms': <Object?>[
        for (final room in snapshot.rooms)
          <String, Object?>{
            'roomId': room.roomId,
            'displayName': room.displayName,
            'lastActivityMs': room.lastActivity.millisecondsSinceEpoch,
            'streamPosition': room.streamPosition,
            if (room.lastEventId != null) 'lastEventId': room.lastEventId,
            if (room.avatarUrl != null) 'avatarUrl': room.avatarUrl,
            'unreadCount': room.unreadCount,
            'highlightCount': room.highlightCount,
            'hasActiveCall': room.hasActiveCall,
            'isFavourite': room.isFavourite,
            'isMuted': room.isMuted,
            'isDirect': room.isDirect,
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
                if (event.senderDisplayName != null)
                  'senderDisplayName': event.senderDisplayName,
                if (event.senderAvatarUrl != null)
                  'senderAvatarUrl': event.senderAvatarUrl,
                'type': event.type,
                'originServerTimestampMs':
                    event.originServerTimestamp.millisecondsSinceEpoch,
                'streamPosition': event.streamPosition,
                if (event.transactionId != null)
                  'transactionId': event.transactionId,
                if (event.redactsEventId != null)
                  'redactsEventId': event.redactsEventId,
                if (event.redacted) 'redacted': true,
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
    if (syncCursor != null &&
        (syncCursor is! String ||
            syncCursor.isEmpty ||
            syncCursor.contains('\u0000'))) {
      return null;
    }
    final rawInvites = document['invites'] ?? const <Object?>[];
    final rawRooms = document['rooms'];
    final rawTimelines = document['timelines'];
    if (rawInvites is! List || rawRooms is! List || rawTimelines is! Map) {
      return null;
    }

    final invites = <MatrixRoomInvite>[];
    for (final rawInvite in rawInvites) {
      if (rawInvite is! Map) return null;
      final invite = _decodeInvite(Map<String, dynamic>.from(rawInvite));
      if (invite == null) return null;
      invites.add(invite);
    }

    final rooms = <MatrixRoomSummary>[];
    for (final rawRoom in rawRooms) {
      if (rawRoom is! Map) return null;
      final room = _decodeRoom(Map<String, dynamic>.from(rawRoom));
      if (room == null) return null;
      rooms.add(room);
    }

    final roomIds = rooms.map((room) => room.roomId).toSet();
    final timelines = <String, List<MatrixTimelineEvent>>{};
    for (final entry in rawTimelines.entries) {
      if (entry.key is! String || entry.value is! List) return null;
      final roomId = entry.key as String;
      if (!_isSafeIdentifier(roomId) || !roomIds.contains(roomId)) return null;
      final events = <MatrixTimelineEvent>[];
      for (final rawEvent in entry.value as List) {
        if (rawEvent is! Map) return null;
        final event = _decodeEvent(Map<String, dynamic>.from(rawEvent));
        if (event == null || event.roomId != roomId) return null;
        events.add(event);
      }
      timelines[roomId] = events;
    }

    return MatrixPresentationSnapshot(
      rooms: rooms,
      invites: invites,
      timelines: timelines,
      syncCursor: syncCursor as String?,
    );
  }

  static MatrixRoomInvite? _decodeInvite(Map<String, dynamic> value) {
    final roomId = value['roomId'];
    final roomName = value['roomName'];
    final inviterId = value['inviterId'];
    final inviterDisplayName = value['inviterDisplayName'];
    final memberCount = value['memberCount'];
    final description = value['description'];
    if (roomId is! String ||
        !_isSafeIdentifier(roomId) ||
        roomName is! String ||
        roomName.trim().isEmpty ||
        roomName.contains('\u0000') ||
        inviterId is! String ||
        !_isSafeIdentifier(inviterId) ||
        inviterDisplayName is! String ||
        inviterDisplayName.trim().isEmpty ||
        inviterDisplayName.contains('\u0000') ||
        memberCount is! int ||
        memberCount < 0 ||
        (description != null &&
            (description is! String ||
                description.trim().isEmpty ||
                description.contains('\u0000')))) {
      return null;
    }
    return MatrixRoomInvite(
      roomId: roomId,
      roomName: roomName,
      inviterId: inviterId,
      inviterDisplayName: inviterDisplayName,
      memberCount: memberCount,
      description: description as String?,
    );
  }

  static MatrixRoomSummary? _decodeRoom(Map<String, dynamic> value) {
    final roomId = value['roomId'];
    final displayName = value['displayName'];
    final lastActivityMs = value['lastActivityMs'];
    final streamPosition = value['streamPosition'];
    final lastEventId = value['lastEventId'];
    final avatarUrl = value['avatarUrl'];
    final unreadCount = value['unreadCount'];
    final highlightCount = value['highlightCount'] ?? 0;
    final hasActiveCall = value['hasActiveCall'] ?? false;
    final isFavourite = value['isFavourite'] ?? false;
    final isMuted = value['isMuted'] ?? false;
    final isDirect = value['isDirect'] ?? false;
    if (roomId is! String ||
        !_isSafeIdentifier(roomId) ||
        displayName is! String ||
        lastActivityMs is! int ||
        streamPosition is! int ||
        (lastEventId != null &&
            (lastEventId is! String || !_isSafeIdentifier(lastEventId))) ||
        (avatarUrl != null &&
            (avatarUrl is! String || !_isSafeIdentifier(avatarUrl))) ||
        unreadCount is! int ||
        highlightCount is! int ||
        highlightCount < 0 ||
        hasActiveCall is! bool ||
        isFavourite is! bool ||
        isMuted is! bool ||
        isDirect is! bool) {
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
      avatarUrl: avatarUrl as String?,
      unreadCount: unreadCount,
      highlightCount: highlightCount,
      hasActiveCall: hasActiveCall,
      isFavourite: isFavourite,
      isMuted: isMuted,
      isDirect: isDirect,
    );
  }

  static bool _isSafeIdentifier(String value) =>
      value.isNotEmpty && !value.contains('\u0000');

  static MatrixTimelineEvent? _decodeEvent(Map<String, dynamic> value) {
    final eventId = value['eventId'];
    final roomId = value['roomId'];
    final senderId = value['senderId'];
    final senderDisplayName = value['senderDisplayName'];
    final senderAvatarUrl = value['senderAvatarUrl'];
    final type = value['type'];
    final timestampMs = value['originServerTimestampMs'];
    final streamPosition = value['streamPosition'];
    final transactionId = value['transactionId'];
    final redactsEventId = value['redactsEventId'];
    final redacted = value['redacted'];
    final content = value['content'];
    if (eventId is! String ||
        !_isSafeIdentifier(eventId) ||
        roomId is! String ||
        !_isSafeIdentifier(roomId) ||
        senderId is! String ||
        !_isSafeIdentifier(senderId) ||
        (senderDisplayName != null &&
            (senderDisplayName is! String ||
                senderDisplayName.trim().isEmpty ||
                senderDisplayName.contains('\u0000'))) ||
        (senderAvatarUrl != null &&
            (senderAvatarUrl is! String ||
                !_isSafeIdentifier(senderAvatarUrl))) ||
        type is! String ||
        !_isSafeIdentifier(type) ||
        timestampMs is! int ||
        streamPosition is! int ||
        (transactionId != null &&
            (transactionId is! String || !_isSafeIdentifier(transactionId))) ||
        (redactsEventId != null &&
            (redactsEventId is! String ||
                !_isSafeIdentifier(redactsEventId))) ||
        (redacted != null && redacted is! bool) ||
        content is! Map) {
      return null;
    }
    return MatrixTimelineEvent(
      eventId: eventId,
      roomId: roomId,
      senderId: senderId,
      senderDisplayName: senderDisplayName as String?,
      senderAvatarUrl: senderAvatarUrl as String?,
      type: type,
      originServerTimestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampMs,
        isUtc: true,
      ),
      streamPosition: streamPosition,
      transactionId: transactionId as String?,
      redactsEventId: redactsEventId as String?,
      redacted: redacted as bool? ?? false,
      content: Map<String, Object?>.from(content),
    );
  }
}
