// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

DateTime? roomListActivityTime(Room room) {
  if (room.lastEvent?.type == EventTypes.refreshingLastEvent) {
    return null;
  }

  final timestamp = room.latestEventReceivedTime;
  return timestamp.millisecondsSinceEpoch == 0 ? null : timestamp;
}

int compareRoomsForChatList(Room a, Room b) {
  if (a.membership != b.membership &&
      (a.membership == Membership.invite ||
          b.membership == Membership.invite)) {
    return a.membership == Membership.invite ? -1 : 1;
  }

  if (a.isFavourite != b.isFavourite) {
    return a.isFavourite ? -1 : 1;
  }

  if (a.isLowPriority != b.isLowPriority) {
    return a.isLowPriority ? 1 : -1;
  }

  final aTimestamp = roomListActivityTime(a)?.millisecondsSinceEpoch ?? 0;
  final bTimestamp = roomListActivityTime(b)?.millisecondsSinceEpoch ?? 0;
  final byActivity = bTimestamp.compareTo(aTimestamp);
  if (byActivity != 0) return byActivity;

  return a.id.compareTo(b.id);
}

/// Sorts a snapshot of rooms while reading each room's mutable sort fields once.
/// Syncs can rebuild the chat list often, and the comparator may otherwise
/// query the same room properties thousands of times during an O(n log n) sort.
void sortRoomsForChatList(List<Room> rooms) {
  final keys =
      <
        String,
        ({bool invite, bool favourite, bool lowPriority, int timestamp})
      >{
        for (final room in rooms)
          room.id: (
            invite: room.membership == Membership.invite,
            favourite: room.isFavourite,
            lowPriority: room.isLowPriority,
            timestamp: room.lastEvent?.type == EventTypes.refreshingLastEvent
                ? 0
                : room.latestEventReceivedTime.millisecondsSinceEpoch,
          ),
      };
  rooms.sort((a, b) {
    final aKey = keys[a.id]!;
    final bKey = keys[b.id]!;
    if (aKey.invite != bKey.invite) return aKey.invite ? -1 : 1;
    if (aKey.favourite != bKey.favourite) return aKey.favourite ? -1 : 1;
    if (aKey.lowPriority != bKey.lowPriority) {
      return aKey.lowPriority ? 1 : -1;
    }
    final byActivity = bKey.timestamp.compareTo(aKey.timestamp);
    return byActivity != 0 ? byActivity : a.id.compareTo(b.id);
  });
}
