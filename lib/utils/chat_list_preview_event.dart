// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

typedef ChatListPreviewDecryptor = Future<Event> Function(Event event);

Future<Event> resolveChatListPreviewEvent(
  Room room,
  Event lastEvent, {
  ChatListPreviewDecryptor? decryptEvent,
}) async {
  if (!_isUndecryptable(lastEvent)) {
    return lastEvent;
  }

  final cachedEvent = await room.client.database.getEventById(
    lastEvent.eventId,
    room,
  );
  var previewEvent = cachedEvent;
  if (previewEvent == null || _isUndecryptable(previewEvent)) {
    previewEvent = decryptEvent == null
        ? await _decryptPreviewEvent(room, lastEvent)
        : await decryptEvent(lastEvent);
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

  late Event decryptedEvent;
  await room.client.database.transaction(() async {
    decryptedEvent = await encryption.decryptRoomEvent(
      event,
      store: true,
      updateType: EventUpdateType.history,
    );
  });
  return decryptedEvent;
}
