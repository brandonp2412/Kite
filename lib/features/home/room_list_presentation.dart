import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:signals/signals.dart';

enum RoomListFilter { all, unreads, people, rooms, favourites }

@immutable
final class JoinedSpace {
  const JoinedSpace({required this.id, required this.name});

  final String id;
  final String name;
}

const deterministicJoinedSpaces = <JoinedSpace>[
  JoinedSpace(id: 'kite-space', name: 'Kite'),
  JoinedSpace(id: 'people-space', name: 'People'),
];

extension RoomListFilterPresentation on RoomListFilter {
  String get label => switch (this) {
    RoomListFilter.all => 'All',
    RoomListFilter.unreads => 'Unreads',
    RoomListFilter.people => 'People',
    RoomListFilter.rooms => 'Rooms',
    RoomListFilter.favourites => 'Favourites',
  };
}

@immutable
final class RoomListEntry {
  const RoomListEntry({
    required this.id,
    required this.name,
    required this.latestEventBody,
    this.latestSender,
    this.unreadCount = 0,
    this.hasMention = false,
    this.hasMutedActivity = false,
    this.hasActiveCall = false,
    this.isMuted = false,
    this.isFavourite = false,
    this.isDirect = false,
    this.spaceIds = const <String>[],
  });

  factory RoomListEntry.fromBenchmark(BenchmarkRoom room) {
    return RoomListEntry(
      id: room.id,
      name: room.name,
      latestEventBody: room.subtitle,
    );
  }

  final String id;
  final String name;
  final String latestEventBody;
  final String? latestSender;
  final int unreadCount;
  final bool hasMention;
  final bool hasMutedActivity;
  final bool hasActiveCall;
  final bool isMuted;
  final bool isFavourite;
  final bool isDirect;
  final List<String> spaceIds;

  bool matches(RoomListFilter filter) => switch (filter) {
    RoomListFilter.all => true,
    RoomListFilter.unreads => unreadCount > 0 || hasMention || hasMutedActivity,
    RoomListFilter.people => isDirect,
    RoomListFilter.rooms => !isDirect,
    RoomListFilter.favourites => isFavourite,
  };

  RoomListEntry copyWith({
    String? latestEventBody,
    String? latestSender,
    int? unreadCount,
    bool? hasMention,
    bool? hasMutedActivity,
    bool? hasActiveCall,
    bool? isMuted,
    bool? isFavourite,
    bool? isDirect,
    List<String>? spaceIds,
  }) {
    return RoomListEntry(
      id: id,
      name: name,
      latestEventBody: latestEventBody ?? this.latestEventBody,
      latestSender: latestSender ?? this.latestSender,
      unreadCount: unreadCount ?? this.unreadCount,
      hasMention: hasMention ?? this.hasMention,
      hasMutedActivity: hasMutedActivity ?? this.hasMutedActivity,
      hasActiveCall: hasActiveCall ?? this.hasActiveCall,
      isMuted: isMuted ?? this.isMuted,
      isFavourite: isFavourite ?? this.isFavourite,
      isDirect: isDirect ?? this.isDirect,
      spaceIds: List<String>.unmodifiable(spaceIds ?? this.spaceIds),
    );
  }
}

final class RoomListStateStore {
  RoomListStateStore(List<RoomListEntry> rooms)
    : roomIds = List<String>.unmodifiable(rooms.map((room) => room.id)),
      _rooms = <String, Signal<RoomListEntry>>{
        for (final room in rooms) room.id: signal(room),
      },
      selectedFilter = signal(RoomListFilter.all),
      selectedSpaceId = signal<String?>(null),
      visibleRoomIds = signal<List<String>>(
        List<String>.unmodifiable(rooms.map((room) => room.id)),
      ) {
    if (_rooms.length != rooms.length) {
      throw ArgumentError.value(rooms, 'rooms', 'Room IDs must be unique.');
    }
  }

  final List<String> roomIds;
  final Map<String, Signal<RoomListEntry>> _rooms;
  final Signal<RoomListFilter> selectedFilter;
  final Signal<String?> selectedSpaceId;
  final Signal<List<String>> visibleRoomIds;

  Signal<RoomListEntry> roomSignal(String roomId) {
    final room = _rooms[roomId];
    if (room == null) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    return room;
  }

  void update(RoomListEntry room) {
    final target = _rooms[room.id];
    if (target == null) {
      throw ArgumentError.value(room.id, 'room.id', 'Unknown room.');
    }
    final filter = selectedFilter.value;
    final spaceId = selectedSpaceId.value;
    final membershipChanged =
        _matches(target.value, filter, spaceId) !=
        _matches(room, filter, spaceId);
    target.value = room;
    if (membershipChanged) {
      _refreshVisibleRoomIds();
    }
  }

  void selectFilter(RoomListFilter filter) {
    if (selectedFilter.value == filter) {
      return;
    }
    selectedFilter.value = filter;
    _refreshVisibleRoomIds();
  }

  void selectSpace(String? spaceId) {
    if (selectedSpaceId.value == spaceId) {
      return;
    }
    selectedSpaceId.value = spaceId;
    _refreshVisibleRoomIds();
  }

  void markAllRead() {
    for (final roomId in roomIds) {
      final target = _rooms[roomId]!;
      final room = target.value;
      if (room.unreadCount == 0 && !room.hasMention && !room.hasMutedActivity) {
        continue;
      }
      target.value = room.copyWith(
        unreadCount: 0,
        hasMention: false,
        hasMutedActivity: false,
      );
    }
    if (selectedFilter.value == RoomListFilter.unreads) {
      _refreshVisibleRoomIds();
    }
  }

  bool _matches(RoomListEntry room, RoomListFilter filter, String? spaceId) {
    return room.matches(filter) &&
        (spaceId == null || room.spaceIds.contains(spaceId));
  }

  void _refreshVisibleRoomIds() {
    final filter = selectedFilter.value;
    final spaceId = selectedSpaceId.value;
    visibleRoomIds.value = List<String>.unmodifiable(
      roomIds.where(
        (roomId) => _matches(_rooms[roomId]!.value, filter, spaceId),
      ),
    );
  }
}

List<RoomListEntry> deterministicRoomListEntries(List<BenchmarkRoom> rooms) {
  return List<RoomListEntry>.unmodifiable(
    rooms.map((room) {
      final base = RoomListEntry.fromBenchmark(room);
      return switch (room.id) {
        'kite' => base.copyWith(
          latestSender: 'Maya',
          latestEventBody: 'The room-list motion trace is clean.',
          unreadCount: 12,
          hasMention: true,
          spaceIds: const <String>['kite-space'],
        ),
        'alice' => base.copyWith(
          latestSender: 'Alice',
          latestEventBody: 'Muted room activity stays quiet.',
          hasMutedActivity: true,
          isMuted: true,
          isDirect: true,
          spaceIds: const <String>['people-space'],
        ),
        'bob' => base.copyWith(
          latestSender: 'Bob',
          latestEventBody: 'Call is active now',
          hasActiveCall: true,
          isDirect: true,
          spaceIds: const <String>['people-space'],
        ),
        'room-3' => base.copyWith(
          latestSender: 'Sam',
          latestEventBody: 'Unread room activity is easy to scan.',
          unreadCount: 4,
          isFavourite: true,
          spaceIds: const <String>['kite-space'],
        ),
        _ => base,
      };
    }),
  );
}
