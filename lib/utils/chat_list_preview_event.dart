// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

typedef ChatListPreviewDecryptor = Future<Event> Function(Event event);

final Map<String, Future<Event>> _previewResolutions = {};

Future<void> preloadChatListPreviewEvents(
  Iterable<Room> rooms, {
  ChatListPreviewDecryptor? decryptEvent,
}) async {
  const batchSize = 8;
  final pending = [
    for (final room in rooms)
      if (room.lastEvent case final event? when _isUndecryptable(event))
        (room, event),
  ];

  for (var offset = 0; offset < pending.length; offset += batchSize) {
    final end = (offset + batchSize).clamp(0, pending.length);
    await Future.wait([
      for (final (room, event) in pending.sublist(offset, end))
        resolveChatListPreviewEvent(room, event, decryptEvent: decryptEvent),
    ]);
    await Future<void>.delayed(Duration.zero);
  }
}

Future<Event> resolveChatListPreviewEvent(
  Room room,
  Event lastEvent, {
  ChatListPreviewDecryptor? decryptEvent,
}) async {
  if (!_isUndecryptable(lastEvent)) {
    return lastEvent;
  }

  final cacheKey = [
    identityHashCode(room.client),
    room.id,
    lastEvent.eventId,
  ].join(':');
  final inFlight = _previewResolutions[cacheKey];
  if (inFlight != null) {
    return inFlight;
  }

  final resolution = Future<Event>(
    () => _resolveChatListPreviewEvent(
      room,
      lastEvent,
      decryptEvent: decryptEvent,
    ),
  );
  _previewResolutions[cacheKey] = resolution;
  try {
    return await resolution;
  } finally {
    if (identical(_previewResolutions[cacheKey], resolution)) {
      _previewResolutions.remove(cacheKey);
    }
  }
}

Future<Event> _resolveChatListPreviewEvent(
  Room room,
  Event lastEvent, {
  ChatListPreviewDecryptor? decryptEvent,
}) async {
  var previewEvent = decryptEvent == null
      ? await _decryptPreviewEvent(room, lastEvent)
      : await decryptEvent(lastEvent);

  if (_isUndecryptable(previewEvent)) {
    final cachedEvent = await room.client.database.getEventById(
      lastEvent.eventId,
      room,
    );
    if (cachedEvent != null && !_isUndecryptable(cachedEvent)) {
      previewEvent = cachedEvent;
    }
  }

  if (_isUndecryptable(previewEvent)) {
    return lastEvent;
  }

  if (room.lastEvent?.eventId == lastEvent.eventId) {
    room.lastEvent = previewEvent;
  }
  return previewEvent;
}

bool _isUndecryptable(Event event) =>
    event.type == EventTypes.Encrypted ||
    event.messageType == MessageTypes.BadEncrypted;

Future<Event> _decryptPreviewEvent(Room room, Event event) async {
  final encryption = room.client.encryption;
  if (encryption == null || !room.client.encryptionEnabled) {
    return event;
  }

  var previewEvent = encryption.decryptRoomEventSync(event);
  if (_isUndecryptable(previewEvent)) {
    previewEvent = await encryption.decryptRoomEvent(event);
  }
  return previewEvent;
}
