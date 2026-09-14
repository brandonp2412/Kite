import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/performance_contract.dart';

@immutable
class BenchmarkRoom {
  const BenchmarkRoom({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final String id;
  final String name;
  final String subtitle;
}

@immutable
class BenchmarkMessage {
  const BenchmarkMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.mine,
  });

  final String id;
  final String sender;
  final String body;
  final bool mine;
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

  static BenchmarkRoom room(String id) =>
      rooms.firstWhere((room) => room.id == id);
}
