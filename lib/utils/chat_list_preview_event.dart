// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

Future<Event> resolveChatListPreviewEvent(Room room, Event lastEvent) async {
  if (lastEvent.type != EventTypes.Encrypted &&
      lastEvent.messageType != MessageTypes.BadEncrypted) {
    return lastEvent;
  }

  final cachedEvent = await room.client.database.getEventById(
    lastEvent.eventId,
    room,
  );
  if (cachedEvent == null ||
      cachedEvent.type == EventTypes.Encrypted ||
      cachedEvent.messageType == MessageTypes.BadEncrypted) {
    return lastEvent;
  }

  if (room.lastEvent?.eventId == lastEvent.eventId) {
    room.lastEvent = cachedEvent;
  }
  return cachedEvent;
}
