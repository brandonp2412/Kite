import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:signals/signals.dart';

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

  RoomListEntry copyWith({
    String? latestEventBody,
    String? latestSender,
    int? unreadCount,
    bool? hasMention,
    bool? hasMutedActivity,
    bool? hasActiveCall,
    bool? isMuted,
    bool? isFavourite,
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
    );
  }
}

final class RoomListStateStore {
  RoomListStateStore(List<RoomListEntry> rooms)
    : roomIds = List<String>.unmodifiable(rooms.map((room) => room.id)),
      _rooms = <String, Signal<RoomListEntry>>{
        for (final room in rooms) room.id: signal(room),
      } {
    if (_rooms.length != rooms.length) {
      throw ArgumentError.value(rooms, 'rooms', 'Room IDs must be unique.');
    }
  }

  final List<String> roomIds;
  final Map<String, Signal<RoomListEntry>> _rooms;

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
    target.value = room;
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
        ),
        'alice' => base.copyWith(
          latestSender: 'Alice',
          latestEventBody: 'Muted room activity stays quiet.',
          hasMutedActivity: true,
          isMuted: true,
        ),
        'bob' => base.copyWith(
          latestSender: 'Bob',
          latestEventBody: 'Call is active now',
          hasActiveCall: true,
        ),
        'room-3' => base.copyWith(
          latestSender: 'Sam',
          latestEventBody: 'Unread room activity is easy to scan.',
          unreadCount: 4,
          isFavourite: true,
        ),
        _ => base,
      };
    }),
  );
}
