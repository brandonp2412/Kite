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

@immutable
final class RoomListSection {
  const RoomListSection({required this.id, required this.name});

  final String id;
  final String name;
}

const deterministicJoinedSpaces = <JoinedSpace>[
  JoinedSpace(id: 'kite-space', name: 'Kite'),
  JoinedSpace(id: 'people-space', name: 'People'),
];

const deterministicRoomListSections = <RoomListSection>[
  RoomListSection(id: 'favourites', name: 'Favourites'),
  RoomListSection(id: 'people', name: 'People'),
  RoomListSection(id: 'rooms', name: 'Rooms'),
];

String _defaultSectionId(RoomListEntry room) {
  if (room.isFavourite) return 'favourites';
  if (room.isDirect) return 'people';
  return 'rooms';
}

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
    MatrixTimelineEvent? latestEvent,
  ) {
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
  RoomListStateStore(
    List<RoomListEntry> rooms, {
    this.sections = deterministicRoomListSections,
  }) : _roomIds = List<String>.unmodifiable(rooms.map((room) => room.id)),
       _rooms = <String, Signal<RoomListEntry>>{
         for (final room in rooms) room.id: signal(room),
       },
       _sectionByRoom = <String, String>{
         for (final room in rooms) room.id: _defaultSectionId(room),
       },
       selectedFilter = signal(RoomListFilter.all),
       selectedSpaceId = signal<String?>(null),
       collapsedSectionIds = signal<Set<String>>(const <String>{}),
       hiddenRoomIds = signal<Set<String>>(const <String>{}),
       sectionLayoutRevision = signal(0),
       visibleRoomIds = signal<List<String>>(
         List<String>.unmodifiable(rooms.map((room) => room.id)),
       ) {
    if (_rooms.length != rooms.length) {
      throw ArgumentError.value(rooms, 'rooms', 'Room IDs must be unique.');
    }
    if (sections.isEmpty ||
        sections.map((section) => section.id).toSet().length !=
            sections.length) {
      throw ArgumentError.value(
        sections,
        'sections',
        'Section IDs must be unique and non-empty.',
      );
    }
    final sectionIds = sections.map((section) => section.id).toSet();
    if (_sectionByRoom.values.any(
      (sectionId) => !sectionIds.contains(sectionId),
    )) {
      throw ArgumentError.value(
        sections,
        'sections',
        'Default room sections must exist.',
      );
    }
    _sectionUnreadCounts = <String, Signal<int>>{
      for (final section in sections)
        section.id: signal(
          rooms.where((room) {
            return _sectionByRoom[room.id] == section.id &&
                _hasUnreadState(room);
          }).length,
        ),
    };
  }

  List<String> _roomIds;
  final Map<String, Signal<RoomListEntry>> _rooms;
  final Map<String, String> _sectionByRoom;
  List<String> get roomIds => _roomIds;
  late final Map<String, Signal<int>> _sectionUnreadCounts;
  final List<RoomListSection> sections;
  final Signal<RoomListFilter> selectedFilter;
  final Signal<String?> selectedSpaceId;
  final Signal<Set<String>> collapsedSectionIds;
  final Signal<Set<String>> hiddenRoomIds;
  final Signal<int> sectionLayoutRevision;
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
    final filter = selectedFilter.value;
    final spaceId = selectedSpaceId.value;
    final membershipChanged =
        _matches(previous, filter, spaceId) != _matches(room, filter, spaceId);
    final previousUnread = _hasUnreadState(previous);
    final nextUnread = _hasUnreadState(room);
    if (!_sameRoom(previous, room)) {
      target.value = room;
    }
    if (previousUnread != nextUnread) {
      final count = _sectionUnreadCounts[_sectionByRoom[room.id]]!;
      count.value += nextUnread ? 1 : -1;
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
    final sectionIds = sections.map((section) => section.id).toSet();
    for (final room in effectiveRooms) {
      if (!_rooms.containsKey(room.id) &&
          !sectionIds.contains(_defaultSectionId(room))) {
        throw ArgumentError.value(
          room,
          'rooms',
          'Default room section must exist.',
        );
      }
    }

    batch(() {
      final incomingIds = ids.toSet();
      for (final roomId in _roomIds.where(
        (roomId) => !incomingIds.contains(roomId),
      )) {
        final previous = _rooms.remove(roomId)?.peek();
        final sectionId = _sectionByRoom.remove(roomId);
        if (previous != null &&
            sectionId != null &&
            _hasUnreadState(previous)) {
          _sectionUnreadCounts[sectionId]!.value--;
        }
      }
      for (final room in effectiveRooms) {
        final target = _rooms[room.id];
        if (target == null) {
          _rooms[room.id] = signal(room);
          final sectionId = _defaultSectionId(room);
          _sectionByRoom[room.id] = sectionId;
          if (_hasUnreadState(room)) {
            _sectionUnreadCounts[sectionId]!.value++;
          }
          continue;
        }
        final previous = target.peek();
        if (_hasUnreadState(previous) != _hasUnreadState(room)) {
          final count = _sectionUnreadCounts[_sectionByRoom[room.id]]!;
          count.value += _hasUnreadState(room) ? 1 : -1;
        }
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
    for (final count in _sectionUnreadCounts.values) {
      if (count.value != 0) {
        count.value = 0;
      }
    }
    if (selectedFilter.value == RoomListFilter.unreads) {
      _refreshVisibleRoomIds();
    }
  }

  String sectionIdFor(String roomId) {
    final sectionId = _sectionByRoom[roomId];
    if (sectionId == null) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    return sectionId;
  }

  List<String> visibleRoomIdsForSection(String sectionId) {
    if (!sections.any((section) => section.id == sectionId)) {
      throw ArgumentError.value(sectionId, 'sectionId', 'Unknown section.');
    }
    return List<String>.unmodifiable(
      visibleRoomIds.value.where(
        (roomId) => _sectionByRoom[roomId] == sectionId,
      ),
    );
  }

  int sectionUnreadCount(String sectionId) {
    final count = _sectionUnreadCounts[sectionId];
    if (count == null) {
      throw ArgumentError.value(sectionId, 'sectionId', 'Unknown section.');
    }
    return count.value;
  }

  void toggleSectionCollapsed(String sectionId) {
    if (!sections.any((section) => section.id == sectionId)) {
      throw ArgumentError.value(sectionId, 'sectionId', 'Unknown section.');
    }
    final next = Set<String>.of(collapsedSectionIds.value);
    if (!next.add(sectionId)) next.remove(sectionId);
    collapsedSectionIds.value = Set<String>.unmodifiable(next);
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

  void moveRoomToSection(String roomId, String sectionId) {
    if (!_sectionByRoom.containsKey(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Unknown room.');
    }
    if (!sections.any((section) => section.id == sectionId)) {
      throw ArgumentError.value(sectionId, 'sectionId', 'Unknown section.');
    }
    final previousSectionId = _sectionByRoom[roomId]!;
    if (previousSectionId == sectionId) return;
    _sectionByRoom[roomId] = sectionId;
    if (_hasUnreadState(_rooms[roomId]!.value)) {
      _sectionUnreadCounts[previousSectionId]!.value--;
      _sectionUnreadCounts[sectionId]!.value++;
    }
    sectionLayoutRevision.value++;
  }

  static bool _hasUnreadState(RoomListEntry room) {
    return room.unreadCount > 0 || room.hasMention || room.hasMutedActivity;
  }

  bool _matches(RoomListEntry room, RoomListFilter filter, String? spaceId) {
    return !hiddenRoomIds.value.contains(room.id) &&
        room.matches(filter) &&
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
        if (!summary.isSpace)
          RoomListEntry.fromMatrix(
            summary,
            _latestTimelineEvent(cache.timelineSignal(roomId).value),
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
