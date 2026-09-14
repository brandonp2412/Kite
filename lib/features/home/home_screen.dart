import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/jitter_injector.dart';
import 'package:kite/design/kite_tokens.dart';
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
          padding: const EdgeInsets.symmetric(vertical: KiteSpacing.sm),
          itemCount: messages.length,
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
    final bubbleColor = mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(KiteRadii.md),
      topRight: const Radius.circular(KiteRadii.md),
      bottomLeft: Radius.circular(mine ? KiteRadii.md : KiteRadii.sm),
      bottomRight: Radius.circular(mine ? KiteRadii.sm : KiteRadii.md),
    );

    final bubble = DecoratedBox(
      key: Key('message-bubble-${message.id}'),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: bubbleRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.sm,
          KiteSpacing.xs,
          KiteSpacing.xs,
          KiteSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message.body,
              key: Key('message-body-${message.id}'),
              style: KiteTypography.body.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: KiteSpacing.xxs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message.timeLabel,
                  style: KiteTypography.metadata.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                if (mine) ...<Widget>[
                  const SizedBox(width: KiteSpacing.xxs),
                  _MessageSendState(roomId: roomId, message: message),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return Padding(
      key: Key('message-row-${message.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: KiteSpacing.md,
        vertical: KiteSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!mine) ...<Widget>[
            _MessageAvatar(sender: message.sender),
            const SizedBox(width: KiteSpacing.xs),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: mine
                  ? bubble
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(
                            left: KiteSpacing.xxs,
                            bottom: KiteSpacing.xxs,
                          ),
                          child: Text(
                            message.sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KiteTypography.metadata.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        bubble,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({required this.sender});

  final String sender;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: '$sender avatar',
      child: CircleAvatar(
        radius: 16,
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        child: Text(
          sender.characters.first.toUpperCase(),
          style: KiteTypography.metadata.copyWith(fontWeight: FontWeight.w700),
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
          width: 44,
          height: 24,
          child: switch (state) {
            TimelineSendState.sending => Center(
              child: Icon(
                Icons.schedule_rounded,
                size: 14,
                color: colors.onSurfaceVariant,
                semanticLabel: 'Sending',
              ),
            ),
            TimelineSendState.sent => Center(
              child: Icon(
                Icons.done_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
                semanticLabel: 'Sent',
              ),
            ),
            TimelineSendState.failed => Tooltip(
              message: 'Retry sending',
              child: InkWell(
                key: Key('retry-${message.id}'),
                borderRadius: BorderRadius.circular(KiteRadii.pill),
                onTap: () => timelineController.retry(roomId, message),
                child: Center(
                  child: Icon(
                    Icons.error_rounded,
                    size: 16,
                    color: colors.error,
                    semanticLabel: 'Message failed. Retry sending',
                  ),
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
    return ColoredBox(
      color: context.kiteColors.canvas,
      child: SizedBox(
        key: const Key('composer'),
        height: 76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.sm,
            KiteSpacing.xs,
            KiteSpacing.md,
            KiteSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                key: const Key('composer-attach'),
                tooltip: 'Add attachment',
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              const SizedBox(width: KiteSpacing.xxs),
              Expanded(
                child: TextField(
                  key: const Key('composer-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 2,
                  textInputAction: TextInputAction.newline,
                  style: KiteTypography.body,
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: KiteSpacing.md,
                      vertical: KiteSpacing.sm,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KiteSpacing.xs),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  final enabled = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    key: const Key('composer-send'),
                    tooltip: 'Send message',
                    onPressed: enabled ? _send : null,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(44),
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
      ),
    );
  }
}
