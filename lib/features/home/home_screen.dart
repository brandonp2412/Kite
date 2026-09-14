import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/jitter_injector.dart';
import 'package:signals/signals_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double sidebarWidth = 320;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          SizedBox(
            key: const Key('sidebar'),
            width: sidebarWidth,
            child: const _RoomList(),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: _ChatPanel()),
        ],
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  const _RoomList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('room-list'),
      itemCount: BenchmarkFixture.rooms.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final room = BenchmarkFixture.rooms[index];
        return SignalBuilder(
          builder: (context) {
            final selected = selectedRoomId.value == room.id;
            return ListTile(
              key: Key('room-${room.id}'),
              selected: selected,
              leading: CircleAvatar(child: Text(room.name.characters.first)),
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
              onTap: () => selectRoom(room.id),
            );
          },
        );
      },
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final roomId = selectedRoomId.value;
        BenchmarkJitterInjector.injectBuildDelay();
        final room = BenchmarkFixture.room(roomId);
        final messages = BenchmarkFixture.messages[roomId]!;

        return Column(
          key: const Key('chat-panel'),
          children: <Widget>[
            SizedBox(
              key: const Key('chat-header'),
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    room.name,
                    key: const Key('chat-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const Key('message-list'),
                reverse: true,
                itemCount: messages.length,
                itemExtent: 54,
                itemBuilder: (context, index) {
                  final message = messages[messages.length - 1 - index];
                  return Align(
                    alignment: message.mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: message.mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            message.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            const SizedBox(
              key: Key('composer'),
              height: 72,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Message',
                    isDense: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
