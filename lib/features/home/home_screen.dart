import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/jitter_injector.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.benchmarkRooms});

  final List<BenchmarkRoom>? benchmarkRooms;

  static const double sidebarWidth = 320;
  static const double tabletSidebarWidth = 300;
  static const double phoneBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < phoneBreakpoint;
    final rooms = benchmarkRooms ?? BenchmarkFixture.rooms;

    if (isPhone) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const _CompactHomeHeader(),
              Expanded(
                child: SizedBox.expand(
                  key: const Key('sidebar'),
                  child: _RoomList(
                    rooms: rooms,
                    onRoomTap: (room) {
                      selectRoom(room.id);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _CompactChatScreen(),
                        ),
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

    final adaptiveSidebarWidth = size.width < 1024
        ? tabletSidebarWidth
        : sidebarWidth;
    return Scaffold(
      body: Row(
        children: <Widget>[
          SizedBox(
            key: const Key('sidebar'),
            width: adaptiveSidebarWidth,
            child: _RoomList(rooms: rooms),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: _ChatPanel()),
        ],
      ),
    );
  }
}

class _CompactHomeHeader extends StatelessWidget {
  const _CompactHomeHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Chats',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
    );
  }
}

class _CompactChatScreen extends StatelessWidget {
  const _CompactChatScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SignalBuilder(
          builder: (context) =>
              Text(BenchmarkFixture.room(selectedRoomId.value).name),
        ),
      ),
      body: const _ChatPanel(showHeader: false),
    );
  }
}

class _RoomList extends StatelessWidget {
  const _RoomList({required this.rooms, this.onRoomTap});

  final List<BenchmarkRoom> rooms;
  final ValueChanged<BenchmarkRoom>? onRoomTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('room-list'),
      itemCount: rooms.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final room = rooms[index];
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
              onTap: () {
                final handler = onRoomTap;
                if (handler != null) {
                  handler(room);
                } else {
                  selectRoom(room.id);
                }
              },
            );
          },
        );
      },
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('chat-panel'),
      children: <Widget>[
        if (showHeader) ...<Widget>[
          const _ChatHeader(),
          const Divider(height: 1),
        ],
        const Expanded(child: _Timeline()),
        const Divider(height: 1),
        const _Composer(),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('chat-header'),
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SignalBuilder(
          builder: (context) {
            final roomId = selectedRoomId.value;
            BenchmarkJitterInjector.injectBuildDelay();
            final room = BenchmarkFixture.room(roomId);
            return Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  child: Text(room.name.characters.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        room.name,
                        key: const Key('chat-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Encrypted conversation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final roomId = selectedRoomId.value;
        final messages = timelineController.messagesFor(roomId).value;
        return ListView.builder(
          key: const Key('message-list'),
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: messages.length,
          itemExtent: 80,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            return _MessageRow(
              key: ValueKey<String>(message.id),
              roomId: roomId,
              message: message,
            );
          },
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({super.key, required this.roomId, required this.message});

  final String roomId;
  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mine = message.mine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 11, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        message.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Text(
                    message.body,
                    key: Key('message-body-${message.id}'),
                    maxLines: mine ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        message.timeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      if (mine) ...<Widget>[
                        const SizedBox(width: 5),
                        _MessageSendState(roomId: roomId, message: message),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageSendState extends StatelessWidget {
  const _MessageSendState({required this.roomId, required this.message});

  final String roomId;
  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final state = message.sendState.value;
        final colors = Theme.of(context).colorScheme;
        return SizedBox(
          key: Key('send-state-${message.id}'),
          height: 18,
          child: switch (state) {
            TimelineSendState.sending => Icon(
              Icons.schedule_rounded,
              size: 13,
              color: colors.onSurfaceVariant,
              semanticLabel: 'Sending',
            ),
            TimelineSendState.sent => Icon(
              Icons.done_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
              semanticLabel: 'Sent',
            ),
            TimelineSendState.failed => InkWell(
              key: Key('retry-${message.id}'),
              borderRadius: BorderRadius.circular(9),
              onTap: () => timelineController.retry(roomId, message),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 13,
                      color: colors.error,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Retry',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          },
        );
      },
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    timelineController.sendText(selectedRoomId.value, body);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('composer'),
      height: 76,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const Key('composer-attach'),
              tooltip: 'Add attachment',
              onPressed: () {},
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                key: const Key('composer-field'),
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final enabled = value.text.trim().isNotEmpty;
                return IconButton.filled(
                  key: const Key('composer-send'),
                  tooltip: 'Send message',
                  onPressed: enabled ? _send : null,
                  style: IconButton.styleFrom(
                    backgroundColor: enabled
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                    foregroundColor: enabled
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                    disabledBackgroundColor: colors.surfaceContainerHighest,
                    disabledForegroundColor: colors.onSurfaceVariant,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
