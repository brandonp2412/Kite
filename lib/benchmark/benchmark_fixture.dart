import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/performance_contract.dart';

@immutable
class BenchmarkRoom {
  const BenchmarkRoom({
    required this.id,
    required this.name,
    required this.subtitle,
    this.isDirect = false,
    this.isUnread = false,
    this.isFavourite = false,
    this.spaceId,
  });

  final String id;
  final String name;
  final String subtitle;
  final bool isDirect;
  final bool isUnread;
  final bool isFavourite;
  final String? spaceId;
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
  static final List<BenchmarkRoom> rooms = List<BenchmarkRoom>.unmodifiable(
    <BenchmarkRoom>[
      const BenchmarkRoom(
        id: 'kite',
        name: 'Kite',
        subtitle: 'Performance test room',
      ),
      const BenchmarkRoom(
        id: 'alice',
        name: 'Alice',
        subtitle: 'Deterministic direct message',
      ),
      const BenchmarkRoom(
        id: 'bob',
        name: 'Bob',
        subtitle: 'Deterministic direct message',
      ),
      ...List<BenchmarkRoom>.generate(
        PerformanceContract.fixtureRoomCount - 3,
        (index) => BenchmarkRoom(
          id: 'room-${index + 3}',
          name: 'User ${index + 3}',
          subtitle: 'Fixture room ${index + 3}',
          isDirect: index % 3 == 0,
          isUnread: index % 4 == 0,
          isFavourite: index % 10 == 0,
          spaceId: 'space-${index % 5}',
        ),
      ),
    ],
  );

  static final Map<String, List<BenchmarkMessage>> messages =
      Map<String, List<BenchmarkMessage>>.unmodifiable(
        <String, List<BenchmarkMessage>>{
          for (final room in rooms)
            room.id: List<BenchmarkMessage>.unmodifiable(
              List<BenchmarkMessage>.generate(
                PerformanceContract.fixtureMessagesPerRoom,
                (index) => BenchmarkMessage(
                  id: '${room.id}-$index',
                  sender: index.isEven ? room.name : 'You',
                  body: 'Deterministic message ${index + 1} in ${room.name}',
                  mine: index.isOdd,
                ),
              ),
            ),
        },
      );

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
