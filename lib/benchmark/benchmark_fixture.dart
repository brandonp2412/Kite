import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/room_list_entry.dart';

@immutable
class BenchmarkRoom extends RoomListEntry {
  const BenchmarkRoom({
    required super.id,
    required super.name,
    required super.subtitle,
    super.latestSender = '',
    super.timeLabel = '',
    int unreadCount = 0,
    super.mentionCount = 0,
    super.isMuted = false,
    super.hasMutedActivity = false,
    super.hasActiveCall = false,
    super.isFavourite = false,
    bool isDirectMessage = false,
    bool? isDirect,
    bool? isUnread,
    this.spaceId,
  }) : super(
         unreadCount: isUnread == true && unreadCount == 0 ? 1 : unreadCount,
         isDirectMessage: isDirect ?? isDirectMessage,
       );

  final String? spaceId;

  bool get isDirect => isDirectMessage;
  bool get isUnread => unreadCount > 0;
}

enum BenchmarkMessageKind {
  text,
  formatted,
  image,
  file,
  audio,
  poll,
  location,
}

@immutable
class BenchmarkMessage {
  const BenchmarkMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.mine,
    this.kind = BenchmarkMessageKind.text,
  });

  final String id;
  final String sender;
  final String body;
  final bool mine;
  final BenchmarkMessageKind kind;
}

abstract final class BenchmarkFixture {
  static final List<BenchmarkRoom>
  rooms = List<BenchmarkRoom>.unmodifiable(<BenchmarkRoom>[
    const BenchmarkRoom(
      id: 'kite',
      name: 'Kite',
      subtitle: 'Pinned benchmark fixture is ready',
      latestSender: 'Kite Bot',
      timeLabel: '17:12',
      unreadCount: 3,
      mentionCount: 1,
      isFavourite: true,
    ),
    const BenchmarkRoom(
      id: 'alice',
      name: 'Alice',
      subtitle: 'See you at 6?',
      latestSender: 'You',
      timeLabel: '17:08',
      hasActiveCall: true,
      isFavourite: true,
      isDirectMessage: true,
    ),
    const BenchmarkRoom(
      id: 'bob',
      name: 'Bob',
      subtitle: 'Can you review the screenshots?',
      latestSender: 'Bob',
      timeLabel: '16:54',
      unreadCount: 12,
      isMuted: true,
      hasMutedActivity: true,
      isDirectMessage: true,
    ),
    ...List<BenchmarkRoom>.generate(
      PerformanceContract.fixtureRoomCount - 3,
      (index) => BenchmarkRoom(
        id: 'room-${index + 3}',
        name: 'User ${index + 3}',
        subtitle: 'Deterministic room-list event ${index + 3}',
        latestSender: index.isEven ? 'You' : 'User ${index + 3}',
        timeLabel:
            '${15 + (index % 3)}:${(index * 7 % 60).toString().padLeft(2, '0')}',
        unreadCount: index % 11 == 0 ? (index % 24) + 1 : 0,
        mentionCount: index % 37 == 0 ? 1 : 0,
        isMuted: index % 13 == 0,
        hasMutedActivity: index % 13 == 0 && index % 2 == 0,
        hasActiveCall: index % 41 == 0,
        isDirect: index % 3 == 0,
        isUnread: index % 4 == 0,
        isFavourite: index % 10 == 0,
        spaceId: 'space-${index % 5}',
      ),
    ),
  ]);

  static final Map<String, List<BenchmarkMessage>> _messagesByRoom =
      <String, List<BenchmarkMessage>>{};

  static List<BenchmarkMessage> messagesFor(String roomId) {
    return _messagesByRoom.putIfAbsent(roomId, () {
      final selectedRoom = room(roomId);
      return List<BenchmarkMessage>.unmodifiable(
        List<BenchmarkMessage>.generate(
          PerformanceContract.fixtureMessagesPerRoom,
          (index) => BenchmarkMessage(
            id: '${selectedRoom.id}-$index',
            sender: index.isEven ? selectedRoom.name : 'You',
            body: 'Deterministic message ${index + 1} in ${selectedRoom.name}',
            mine: index.isOdd,
          ),
        ),
      );
    });
  }

  static final List<BenchmarkRoom> largeRoomListRooms =
      List<BenchmarkRoom>.unmodifiable(
        List<BenchmarkRoom>.generate(
          PerformanceContract.roomListBenchmarkRoomCount,
          (index) => BenchmarkRoom(
            id: 'scroll-room-$index',
            name: 'Benchmark room ${index + 1}',
            subtitle: 'Deterministic room-list benchmark ${index + 1}',
            isDirect: index % 3 == 0,
            isUnread: index % 4 == 0,
            isFavourite: index % 10 == 0,
            spaceId: 'space-${index % 5}',
          ),
        ),
      );

  static final List<BenchmarkMessage> richTimelineMessages =
      List<BenchmarkMessage>.unmodifiable(
        _timelinePage(
          prefix: 'timeline',
          startIndex: 0,
          count: PerformanceContract.timelineBenchmarkMessageCount,
        ),
      );

  static final List<BenchmarkMessage> olderTimelinePage =
      List<BenchmarkMessage>.unmodifiable(
        _timelinePage(
          prefix: 'older',
          startIndex: -PerformanceContract.paginationBenchmarkPageSize,
          count: PerformanceContract.paginationBenchmarkPageSize,
        ),
      );

  static const BenchmarkMessage incomingTimelineMessage = BenchmarkMessage(
    id: 'incoming-timeline-message',
    sender: 'Alice',
    body: 'A deterministic incoming benchmark message',
    mine: false,
    kind: BenchmarkMessageKind.formatted,
  );

  static List<BenchmarkMessage> _timelinePage({
    required String prefix,
    required int startIndex,
    required int count,
  }) {
    final kinds = BenchmarkMessageKind.values;
    return List<BenchmarkMessage>.generate(count, (offset) {
      final index = startIndex + offset;
      final kind = kinds[offset % kinds.length];
      return BenchmarkMessage(
        id: '$prefix-$index',
        sender: offset.isEven ? 'Alice' : 'You',
        body: switch (kind) {
          BenchmarkMessageKind.text => 'Message $index',
          BenchmarkMessageKind.formatted => 'Formatted update $index',
          BenchmarkMessageKind.image => 'Image attachment $index',
          BenchmarkMessageKind.file => 'Document-$index.pdf',
          BenchmarkMessageKind.audio => 'Voice message $index',
          BenchmarkMessageKind.poll => 'Poll response $index',
          BenchmarkMessageKind.location => 'Shared location $index',
        },
        mine: offset.isOdd,
        kind: kind,
      );
    });
  }

  static BenchmarkRoom room(String id) =>
      rooms.firstWhere((room) => room.id == id);
}
