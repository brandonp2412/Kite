import 'package:kite/features/home/room_list_entry.dart';
import 'package:signals/signals.dart';

enum RoomListFilter { all, unreads, people, rooms, favourites }

final activeRoomListFilter = signal(RoomListFilter.all);

void selectRoomListFilter(RoomListFilter filter) {
  if (activeRoomListFilter.value == filter) return;
  activeRoomListFilter.value = filter;
}

bool roomMatchesFilter(RoomListEntry room, RoomListFilter filter) {
  return switch (filter) {
    RoomListFilter.all => true,
    RoomListFilter.unreads => room.unreadCount > 0 || room.mentionCount > 0,
    RoomListFilter.people => room.isDirectMessage,
    RoomListFilter.rooms => !room.isDirectMessage,
    RoomListFilter.favourites => room.isFavourite,
  };
}

extension RoomListFilterLabel on RoomListFilter {
  String get label => switch (this) {
    RoomListFilter.all => 'All',
    RoomListFilter.unreads => 'Unreads',
    RoomListFilter.people => 'People',
    RoomListFilter.rooms => 'Rooms',
    RoomListFilter.favourites => 'Favourites',
  };
}
