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
    return a.isFavourite ? 1 : -1;
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
