import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
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
    this.unreadThreadCount = 0,
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

  factory RoomListEntry.fromMatrix(
    MatrixRoomSummary summary,
    MatrixTimelineEvent? latestEvent,
  ) {
    final body = latestEvent?.content['body'];
    return RoomListEntry(
      id: summary.roomId,
      name: summary.displayName,
      latestEventBody: body is String && body.trim().isNotEmpty
          ? body.trim()
          : latestEvent == null
          ? ''
          : _fallbackPreview(latestEvent),
      latestSender: latestEvent?.senderId,
      unreadCount: summary.unreadCount,
    );
  }

  final String id;
  final String name;
  final String latestEventBody;
  final String? latestSender;
  final int unreadCount;
  final int unreadThreadCount;
  final bool hasMention;
  final bool hasMutedActivity;
  final bool hasActiveCall;
  final bool isMuted;
  final bool isFavourite;
  final bool isDirect;
  final List<String> spaceIds;

  bool matches(RoomListFilter filter) => switch (filter) {
    RoomListFilter.all => true,
    RoomListFilter.unreads =>
      unreadCount > 0 ||
          unreadThreadCount > 0 ||
          hasMention ||
          hasMutedActivity,
    RoomListFilter.people => isDirect,
    RoomListFilter.rooms => !isDirect,
    RoomListFilter.favourites => isFavourite,
  };

  RoomListEntry copyWith({
    String? latestEventBody,
    String? latestSender,
    int? unreadCount,
    int? unreadThreadCount,
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
      unreadThreadCount: unreadThreadCount ?? this.unreadThreadCount,
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
    : _roomIds = List<String>.unmodifiable(rooms.map((room) => room.id)),
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

  List<String> _roomIds;
  final Map<String, Signal<RoomListEntry>> _rooms;
  List<String> get roomIds => _roomIds;
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
    if (!_sameRoom(target.peek(), room)) {
      target.value = room;
    }
    if (membershipChanged) {
      _refreshVisibleRoomIds();
    }
  }

  void reconcile(List<RoomListEntry> rooms) {
    final ids = rooms.map((room) => room.id).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      throw ArgumentError.value(rooms, 'rooms', 'Room IDs must be unique.');
    }

    batch(() {
      final incomingIds = ids.toSet();
      _rooms.removeWhere((roomId, _) => !incomingIds.contains(roomId));
      for (final room in rooms) {
        final target = _rooms[room.id];
        if (target == null) {
          _rooms[room.id] = signal(room);
        } else if (!_sameRoom(target.peek(), room)) {
          target.value = room;
        }
      }
      _roomIds = List<String>.unmodifiable(ids);
      _refreshVisibleRoomIds();
    });
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
      if (room.unreadCount == 0 &&
          room.unreadThreadCount == 0 &&
          !room.hasMention &&
          !room.hasMutedActivity) {
        continue;
      }
      target.value = room.copyWith(
        unreadCount: 0,
        unreadThreadCount: 0,
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
    final next = List<String>.unmodifiable(
      roomIds.where(
        (roomId) => _matches(_rooms[roomId]!.value, filter, spaceId),
      ),
    );
    if (!listEquals(visibleRoomIds.peek(), next)) {
      visibleRoomIds.value = next;
    }
  }
}

List<RoomListEntry> matrixRoomListEntries(MatrixPresentationCache cache) {
  return List<RoomListEntry>.unmodifiable(<RoomListEntry>[
    for (final roomId in cache.roomOrder.value)
      if (cache.roomSummarySignal(roomId).value case final summary?)
        RoomListEntry.fromMatrix(
          summary,
          _latestTimelineEvent(cache.timelineSignal(roomId).value),
        ),
  ]);
}

MatrixTimelineEvent? _latestTimelineEvent(List<MatrixTimelineEvent> events) {
  return events.isEmpty ? null : events.last;
}

bool _sameRoom(RoomListEntry left, RoomListEntry right) {
  return left.id == right.id &&
      left.name == right.name &&
      left.latestEventBody == right.latestEventBody &&
      left.latestSender == right.latestSender &&
      left.unreadCount == right.unreadCount &&
      left.unreadThreadCount == right.unreadThreadCount &&
      left.hasMention == right.hasMention &&
      left.hasMutedActivity == right.hasMutedActivity &&
      left.hasActiveCall == right.hasActiveCall &&
      left.isMuted == right.isMuted &&
      left.isFavourite == right.isFavourite &&
      left.isDirect == right.isDirect &&
      listEquals(left.spaceIds, right.spaceIds);
}

String _fallbackPreview(MatrixTimelineEvent event) {
  if (event.type != 'm.room.message') return 'Room activity';
  return switch (event.content['msgtype']) {
    'm.image' => 'Image',
    'm.video' => 'Video',
    'm.audio' => 'Audio',
    'm.file' => 'File',
    'm.notice' => 'Notice',
    'm.emote' => 'Message',
    _ => 'Message',
  };
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
