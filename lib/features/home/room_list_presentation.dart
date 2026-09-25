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

  Set<RoomListFilter> get incompatibleFilters => switch (this) {
    RoomListFilter.people => const <RoomListFilter>{RoomListFilter.rooms},
    RoomListFilter.rooms => const <RoomListFilter>{RoomListFilter.people},
    _ => const <RoomListFilter>{},
  };
}

@immutable
final class RoomListEntry {
  const RoomListEntry({
    required this.id,
    required this.name,
    required this.latestEventBody,
    this.latestSender,
    this.avatarUrl,
    this.unreadCount = 0,
    this.unreadThreadCount = 0,
    this.hasMention = false,
    this.hasMutedActivity = false,
    this.hasActiveCall = false,
    this.isMuted = false,
    this.isFavourite = false,
    this.isDirect = false,
    this.isPendingSync = false,
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
    MatrixTimelineEvent? latestEvent, {
    List<String> spaceIds = const <String>[],
  }) {
    return RoomListEntry(
      id: summary.roomId,
      name: summary.displayName,
      latestEventBody: latestEvent == null
          ? ''
          : _latestEventPreview(latestEvent),
      latestSender: latestEvent?.senderDisplayName ?? latestEvent?.senderId,
      avatarUrl: summary.avatarUrl,
      unreadCount: summary.unreadCount,
      hasMention: summary.highlightCount > 0,
      hasMutedActivity: summary.isMuted && summary.unreadCount > 0,
      hasActiveCall: summary.hasActiveCall,
      isMuted: summary.isMuted,
      isFavourite: summary.isFavourite,
      isDirect: summary.isDirect,
      spaceIds: List<String>.unmodifiable(spaceIds),
    );
  }

  final String id;
  final String name;
  final String latestEventBody;
  final String? latestSender;
  final String? avatarUrl;
  final int unreadCount;
  final int unreadThreadCount;
  final bool hasMention;
  final bool hasMutedActivity;
  final bool hasActiveCall;
  final bool isMuted;
  final bool isFavourite;
  final bool isDirect;
  final bool isPendingSync;
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
    String? avatarUrl,
    int? unreadCount,
    int? unreadThreadCount,
    bool? hasMention,
    bool? hasMutedActivity,
    bool? hasActiveCall,
    bool? isMuted,
    bool? isFavourite,
    bool? isDirect,
    bool? isPendingSync,
    List<String>? spaceIds,
  }) {
    return RoomListEntry(
      id: id,
      name: name,
      latestEventBody: latestEventBody ?? this.latestEventBody,
      latestSender: latestSender ?? this.latestSender,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      unreadCount: unreadCount ?? this.unreadCount,
      unreadThreadCount: unreadThreadCount ?? this.unreadThreadCount,
      hasMention: hasMention ?? this.hasMention,
      hasMutedActivity: hasMutedActivity ?? this.hasMutedActivity,
      hasActiveCall: hasActiveCall ?? this.hasActiveCall,
      isMuted: isMuted ?? this.isMuted,
      isFavourite: isFavourite ?? this.isFavourite,
      isDirect: isDirect ?? this.isDirect,
      isPendingSync: isPendingSync ?? this.isPendingSync,
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
      selectedFilters = signal<Set<RoomListFilter>>(const <RoomListFilter>{}),
      selectedSpaceId = signal<String?>(null),
      hiddenRoomIds = signal<Set<String>>(const <String>{}),
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
  final Signal<Set<RoomListFilter>> selectedFilters;
  final Signal<String?> selectedSpaceId;
  final Signal<Set<String>> hiddenRoomIds;
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
    final previous = target.value;
    final filters = selectedFilters.value;
    final spaceId = selectedSpaceId.value;
    final membershipChanged =
        _matches(previous, filters, spaceId) !=
        _matches(room, filters, spaceId);
    if (!_sameRoom(previous, room)) {
      target.value = room;
    }
    if (membershipChanged) {
      _refreshVisibleRoomIds();
    }
  }

  void reconcile(List<RoomListEntry> rooms) {
    final incomingIds = rooms.map((room) => room.id).toSet();
    final retainedPendingRooms = <RoomListEntry>[
      for (final roomId in _roomIds)
        if (!incomingIds.contains(roomId) &&
            _rooms[roomId]!.peek().isPendingSync)
          _rooms[roomId]!.peek(),
    ];
    final effectiveRooms = <RoomListEntry>[...retainedPendingRooms, ...rooms];
    final ids = effectiveRooms.map((room) => room.id).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      throw ArgumentError.value(rooms, 'rooms', 'Room IDs must be unique.');
    }

    batch(() {
      final incomingIds = ids.toSet();
      for (final roomId in _roomIds.where(
        (roomId) => !incomingIds.contains(roomId),
      )) {
        _rooms.remove(roomId);
      }
      for (final room in effectiveRooms) {
        final target = _rooms[room.id];
        if (target == null) {
          _rooms[room.id] = signal(room);
          continue;
        }
        final previous = target.peek();
        if (!_sameRoom(previous, room)) {
          target.value = room;
        }
      }
      _roomIds = List<String>.unmodifiable(ids);
      final retainedHidden = hiddenRoomIds.peek().intersection(incomingIds);
      if (!setEquals(hiddenRoomIds.peek(), retainedHidden)) {
        hiddenRoomIds.value = Set<String>.unmodifiable(retainedHidden);
      }
      _refreshVisibleRoomIds();
    });
  }

  void addPendingRoom(RoomListEntry room) {
    if (!room.isPendingSync) {
      throw ArgumentError.value(
        room,
        'room',
        'Locally created rooms must be pending sync.',
      );
    }
    reconcile(<RoomListEntry>[
      room,
      for (final roomId in _roomIds)
        if (roomId != room.id) _rooms[roomId]!.peek(),
    ]);
  }

  void selectFilter(RoomListFilter filter) {
    final next = filter == RoomListFilter.all
        ? const <RoomListFilter>{}
        : <RoomListFilter>{filter};
    if (setEquals(selectedFilters.value, next)) {
      return;
    }
    selectedFilters.value = Set<RoomListFilter>.unmodifiable(next);
    selectedFilter.value = filter;
    _refreshVisibleRoomIds();
  }

  void toggleFilter(RoomListFilter filter) {
    if (filter == RoomListFilter.all) {
      clearFilters();
      return;
    }
    final next = Set<RoomListFilter>.of(selectedFilters.value);
    if (!next.remove(filter)) {
      if (next.any(filter.incompatibleFilters.contains)) {
        return;
      }
      next.add(filter);
    }
    selectedFilters.value = Set<RoomListFilter>.unmodifiable(next);
    selectedFilter.value = next.isEmpty ? RoomListFilter.all : next.last;
    _refreshVisibleRoomIds();
  }

  void clearFilters() {
    if (selectedFilters.value.isEmpty) {
      return;
    }
    selectedFilters.value = const <RoomListFilter>{};
    selectedFilter.value = RoomListFilter.all;
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
    if (selectedFilters.value.contains(RoomListFilter.unreads)) {
      _refreshVisibleRoomIds();
    }
  }

  void hideRoom(String roomId) {
    if (!_rooms.containsKey(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    final next = <String>{...hiddenRoomIds.value};
    if (!next.add(roomId)) return;
    hiddenRoomIds.value = Set<String>.unmodifiable(next);
    _refreshVisibleRoomIds();
  }

  void showRoom(String roomId) {
    if (!_rooms.containsKey(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    final next = <String>{...hiddenRoomIds.value};
    if (!next.remove(roomId)) return;
    hiddenRoomIds.value = Set<String>.unmodifiable(next);
    _refreshVisibleRoomIds();
  }

  bool isRoomHidden(String roomId) => hiddenRoomIds.value.contains(roomId);

  void setFavourite(String roomId, bool isFavourite) {
    final target = _rooms[roomId];
    if (target == null) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    if (target.value.isFavourite == isFavourite) return;
    update(target.value.copyWith(isFavourite: isFavourite));
  }

  void toggleFavourite(String roomId) {
    final target = _rooms[roomId];
    if (target == null) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    setFavourite(roomId, !target.value.isFavourite);
  }

  bool _matches(
    RoomListEntry room,
    Set<RoomListFilter> filters,
    String? spaceId,
  ) {
    return !hiddenRoomIds.value.contains(room.id) &&
        filters.every(room.matches) &&
        (spaceId == null || room.spaceIds.contains(spaceId));
  }

  void _refreshVisibleRoomIds() {
    final filters = selectedFilters.value;
    final spaceId = selectedSpaceId.value;
    final next = List<String>.unmodifiable(
      roomIds.where(
        (roomId) => _matches(_rooms[roomId]!.value, filters, spaceId),
      ),
    );
    if (!listEquals(visibleRoomIds.peek(), next)) {
      visibleRoomIds.value = next;
    }
  }
}

List<RoomListEntry> matrixRoomListEntries(MatrixPresentationCache cache) {
  final spaceIdsByRoom = <String, List<String>>{};
  for (final roomId in cache.roomOrder.value) {
    final summary = cache.roomSummarySignal(roomId).value;
    if (summary == null || !summary.isSpace) continue;
    for (final childRoomId in summary.childRoomIds) {
      (spaceIdsByRoom[childRoomId] ??= <String>[]).add(summary.roomId);
    }
  }

  return List<RoomListEntry>.unmodifiable(<RoomListEntry>[
    for (final roomId in cache.roomOrder.value)
      if (cache.roomSummarySignal(roomId).value case final summary?)
        if (!summary.isSpace)
          RoomListEntry.fromMatrix(
            summary,
            _latestTimelineEvent(cache.timelineSignal(roomId).value),
            spaceIds: spaceIdsByRoom[summary.roomId] ?? const <String>[],
          ),
  ]);
}

MatrixTimelineEvent? _latestTimelineEvent(List<MatrixTimelineEvent> events) {
  if (events.isEmpty) return null;
  for (final event in events.reversed) {
    if (event.type == 'm.room.message') return event;
  }
  return events.last;
}

bool _sameRoom(RoomListEntry left, RoomListEntry right) {
  return left.id == right.id &&
      left.name == right.name &&
      left.latestEventBody == right.latestEventBody &&
      left.latestSender == right.latestSender &&
      left.avatarUrl == right.avatarUrl &&
      left.unreadCount == right.unreadCount &&
      left.unreadThreadCount == right.unreadThreadCount &&
      left.hasMention == right.hasMention &&
      left.hasMutedActivity == right.hasMutedActivity &&
      left.hasActiveCall == right.hasActiveCall &&
      left.isMuted == right.isMuted &&
      left.isFavourite == right.isFavourite &&
      left.isDirect == right.isDirect &&
      left.isPendingSync == right.isPendingSync &&
      listEquals(left.spaceIds, right.spaceIds);
}

String _latestEventPreview(MatrixTimelineEvent event) {
  if (event.redacted) return 'Message deleted';
  if (event.type == 'm.room.encrypted') return 'Unable to decrypt message';
  if (event.type != 'm.room.message') return 'Room activity';
  final newContent = event.content['m.new_content'];
  final relatesTo = event.content['m.relates_to'];
  final content =
      relatesTo is Map &&
          relatesTo['rel_type'] == 'm.replace' &&
          newContent is Map
      ? newContent
      : event.content;
  final body = content['body'];
  final text = body is String ? body.trim() : '';
  return switch (content['msgtype']) {
    'm.image' => 'Image',
    'm.video' => 'Video',
    'm.audio' when content.containsKey('org.matrix.msc3245.voice') =>
      'Voice message',
    'm.audio' => 'Audio',
    'm.file' => 'File',
    'm.text' || 'm.notice' || 'm.emote' => text.isEmpty ? 'Message' : text,
    _ => text.isEmpty ? 'Message' : text,
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
