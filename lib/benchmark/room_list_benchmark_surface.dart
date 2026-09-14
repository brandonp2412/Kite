import 'package:flutter/material.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';

enum BenchmarkRoomFilter { all, unread, people, rooms, favourites }

class RoomListBenchmarkController {
  RoomListBenchmarkController({List<BenchmarkRoom>? rooms})
    : _rooms = rooms ?? BenchmarkFixture.largeRoomListRooms,
      visibleRooms = ValueNotifier<List<BenchmarkRoom>>(
        List<BenchmarkRoom>.unmodifiable(
          rooms ?? BenchmarkFixture.largeRoomListRooms,
        ),
      );

  final List<BenchmarkRoom> _rooms;
  final ValueNotifier<List<BenchmarkRoom>> visibleRooms;

  String _query = '';
  BenchmarkRoomFilter _filter = BenchmarkRoomFilter.all;
  String? _spaceId;

  BenchmarkRoomFilter get filter => _filter;
  String? get spaceId => _spaceId;

  void search(String query) {
    _query = query.trim().toLowerCase();
    _recompute();
  }

  void selectFilter(BenchmarkRoomFilter filter) {
    _filter = filter;
    _recompute();
  }

  void selectSpace(String? spaceId) {
    _spaceId = spaceId;
    _recompute();
  }

  void _recompute() {
    visibleRooms.value = List<BenchmarkRoom>.unmodifiable(
      _rooms.where((room) {
        if (_spaceId != null && room.spaceId != _spaceId) {
          return false;
        }
        if (!_matchesFilter(room)) {
          return false;
        }
        if (_query.isEmpty) {
          return true;
        }
        return room.name.toLowerCase().contains(_query) ||
            room.subtitle.toLowerCase().contains(_query);
      }),
    );
  }

  bool _matchesFilter(BenchmarkRoom room) => switch (_filter) {
    BenchmarkRoomFilter.all => true,
    BenchmarkRoomFilter.unread => room.isUnread,
    BenchmarkRoomFilter.people => room.isDirect,
    BenchmarkRoomFilter.rooms => !room.isDirect,
    BenchmarkRoomFilter.favourites => room.isFavourite,
  };

  void dispose() => visibleRooms.dispose();
}

class RoomListBenchmarkSurface extends StatelessWidget {
  const RoomListBenchmarkSurface({required this.controller, super.key});

  final RoomListBenchmarkController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text('Room-list performance fixture'),
                    ),
                    ValueListenableBuilder<List<BenchmarkRoom>>(
                      valueListenable: controller.visibleRooms,
                      builder: (context, rooms, child) => Text(
                        '${rooms.length} rooms',
                        key: const Key('benchmark-visible-room-count'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<List<BenchmarkRoom>>(
                valueListenable: controller.visibleRooms,
                builder: (context, rooms, child) => ListView.builder(
                  key: const Key('benchmark-room-list'),
                  itemCount: rooms.length,
                  itemExtent: 72,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return ListTile(
                      key: Key('benchmark-room-${room.id}'),
                      leading: CircleAvatar(
                        child: Text(room.name.characters.first),
                      ),
                      title: Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        room.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: room.isUnread
                          ? const Icon(Icons.circle, size: 10)
                          : null,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
