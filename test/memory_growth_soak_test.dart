import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  test('repeated room switching and pagination keep retained timeline state bounded', () {
    const roomCount = 24;
    const initialEventsPerRoom = 60;
    const pageEventsPerRoom = 40;
    const soakCycles = 40;

    final rooms = List<MatrixRoomSummary>.generate(
      roomCount,
      (roomIndex) => MatrixRoomSummary(
        roomId: '!room$roomIndex:kite.test',
        displayName: 'Room $roomIndex',
        lastActivity: DateTime.utc(2026, 9, 15, 5, roomIndex),
        streamPosition: roomIndex,
      ),
      growable: false,
    );
    final initialTimelines = <String, List<MatrixTimelineEvent>>{
      for (var roomIndex = 0; roomIndex < roomCount; roomIndex++)
        rooms[roomIndex].roomId: _events(
          roomId: rooms[roomIndex].roomId,
          prefix: 'initial',
          count: initialEventsPerRoom,
          startingPosition: pageEventsPerRoom,
        ),
    };
    final olderPages = <String, List<MatrixTimelineEvent>>{
      for (var roomIndex = 0; roomIndex < roomCount; roomIndex++)
        rooms[roomIndex].roomId: _events(
          roomId: rooms[roomIndex].roomId,
          prefix: 'older',
          count: pageEventsPerRoom,
          startingPosition: 0,
        ),
    };
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: rooms,
        timelines: initialTimelines,
      ),
    );
    final roomOrder = cache.roomOrder.value;
    final timelineSignals = <String, Object>{
      for (final room in rooms) room.roomId: cache.timelineSignal(room.roomId),
    };

    for (final room in rooms) {
      cache.applySync(
        MatrixSyncBatch(
          cursor: 'first-page-${room.roomId}',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: room.roomId,
              timelineEvents: olderPages[room.roomId]!,
            ),
          ],
        ),
      );
    }

    final stableTimelineValues = <String, List<MatrixTimelineEvent>>{
      for (final room in rooms)
        room.roomId: cache.timelineSignal(room.roomId).value,
    };
    final expectedRetainedEvents =
        roomCount * (initialEventsPerRoom + pageEventsPerRoom);
    expect(_retainedEventCount(cache, rooms), expectedRetainedEvents);

    for (var cycle = 0; cycle < soakCycles; cycle++) {
      for (var offset = 0; offset < roomCount; offset++) {
        final room = rooms[(cycle + offset) % roomCount];
        final signal = cache.timelineSignal(room.roomId);
        expect(signal, same(timelineSignals[room.roomId]));

        cache.applySync(
          MatrixSyncBatch(
            cursor: 'soak-$cycle-$offset',
            rooms: <MatrixRoomDelta>[
              MatrixRoomDelta(
                roomId: room.roomId,
                timelineEvents: olderPages[room.roomId]!,
              ),
            ],
          ),
        );

        expect(signal.value, same(stableTimelineValues[room.roomId]));
        expect(
          signal.value,
          hasLength(initialEventsPerRoom + pageEventsPerRoom),
        );
        expect(cache.roomOrder.value, same(roomOrder));
      }
    }

    expect(_retainedEventCount(cache, rooms), expectedRetainedEvents);
  });
}

List<MatrixTimelineEvent> _events({
  required String roomId,
  required String prefix,
  required int count,
  required int startingPosition,
}) {
  return List<MatrixTimelineEvent>.generate(count, (index) {
    final position = startingPosition + index;
    return MatrixTimelineEvent(
      eventId: '\$$prefix-$roomId-$position',
      roomId: roomId,
      senderId: '@alice:kite.test',
      type: 'm.room.message',
      originServerTimestamp: DateTime.utc(
        2026,
        9,
        15,
      ).add(Duration(seconds: position)),
      streamPosition: position,
      content: <String, Object?>{'body': '$prefix message $position'},
    );
  }, growable: false);
}

int _retainedEventCount(
  MatrixPresentationCache cache,
  List<MatrixRoomSummary> rooms,
) {
  var count = 0;
  for (final room in rooms) {
    count += cache.timelineSignal(room.roomId).value.length;
  }
  return count;
}
