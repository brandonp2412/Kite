import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

typedef _ComposerAction = void Function(String roomId, TimelineMessage message);

enum _MessageAction {
  reply,
  edit,
  copy,
  forward,
  report,
  redact,
  reactionPicker,
}

const List<String> _quickReactions = <String>['👍', '❤️', '😂', '🎉', '😮'];
const List<String> _reportReasons = <String>[
  'Spam or scam',
  'Harassment or abuse',
  'Inappropriate content',
  'Other',
];

const List<String> _reactionPickerEmoji = <String>[
  '👍',
  '👎',
  '❤️',
  '😂',
  '🎉',
  '😮',
  '😢',
  '😡',
  '🔥',
  '👏',
  '🙌',
  '🤔',
  '👀',
  '✅',
  '💯',
  '🚀',
  '🥳',
  '🙏',
  '🤝',
  '💡',
  '⭐',
  '💜',
  '✨',
  '🤯',
];

enum _ComposerMode { reply, edit }

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({this.showHeader = true});

  final bool showHeader;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final GlobalKey<_ComposerState> _composerKey = GlobalKey<_ComposerState>();

  void _reply(String roomId, TimelineMessage message) {
    _composerKey.currentState?.beginReply(roomId, message);
  }

  void _edit(String roomId, TimelineMessage message) {
    _composerKey.currentState?.beginEdit(roomId, message);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('chat-panel'),
      children: <Widget>[
        if (widget.showHeader) ...<Widget>[
          const _ChatHeader(),
          const Divider(height: 1),
        ],
        Expanded(
          child: _Timeline(onReply: _reply, onEdit: _edit),
        ),
        const Divider(height: 1),
        _Composer(key: _composerKey),
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
  const _Timeline({required this.onReply, required this.onEdit});

  final _ComposerAction onReply;
  final _ComposerAction onEdit;

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
              onReply: onReply,
              onEdit: onEdit,
            );
          },
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.roomId,
    required this.message,
    required this.onReply,
    required this.onEdit,
  });

  final String roomId;
  final TimelineMessage message;
  final _ComposerAction onReply;
  final _ComposerAction onEdit;

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.kiteColors.canvas,
      constraints: const BoxConstraints(maxWidth: 440),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
      ),
      builder: (sheetContext) => _MessageActionSheet(message: message),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _MessageAction.reply:
        onReply(roomId, message);
      case _MessageAction.edit:
        onEdit(roomId, message);
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.body));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Message copied'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
      case _MessageAction.forward:
        final destinations = await showModalBottomSheet<List<String>>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: context.kiteColors.canvas,
          constraints: const BoxConstraints(maxWidth: 440),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KiteRadii.lg),
            ),
          ),
          builder: (sheetContext) =>
              _ForwardMessageSheet(currentRoomId: roomId, message: message),
        );
        if (!context.mounted || destinations == null || destinations.isEmpty) {
          return;
        }
        final forwarded = timelineController.forwardText(message, destinations);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Forwarded to ${forwarded.length} ${forwarded.length == 1 ? 'room' : 'rooms'}',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      case _MessageAction.report:
        final reason = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          backgroundColor: context.kiteColors.canvas,
          constraints: const BoxConstraints(maxWidth: 440),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KiteRadii.lg),
            ),
          ),
          builder: (sheetContext) => _ReportMessageSheet(message: message),
        );
        if (!context.mounted || reason == null) return;
        await timelineController.reportMessage(roomId, message, reason);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Report sent'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
      case _MessageAction.reactionPicker:
        final emoji = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          backgroundColor: context.kiteColors.canvas,
          constraints: const BoxConstraints(maxWidth: 440),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KiteRadii.lg),
            ),
          ),
          builder: (pickerContext) => const _ReactionPickerSheet(),
        );
        if (!context.mounted || emoji == null) return;
        timelineController.toggleReaction(message, emoji);
      case _MessageAction.redact:
        final route = DialogRoute<bool>(
          context: context,
          builder: (dialogContext) => const _DeleteMessageDialog(),
        );
        final confirmed = await Navigator.of(
          context,
          rootNavigator: true,
        ).push(route);
        await route.completed;
        if (!context.mounted) return;
        if (confirmed == true) {
          timelineController.redactText(message);
        }
    }
  }

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

    final bubble = GestureDetector(
      onLongPress: () => _showActions(context),
      onSecondaryTap: () => _showActions(context),
      child: DecoratedBox(
        key: Key('message-bubble-${message.id}'),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
        ),
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
              if (message.isReply) ...<Widget>[
                _MessageReplyPreview(message: message),
                const SizedBox(height: KiteSpacing.xs),
              ],
              SignalBuilder(
                builder: (context) {
                  if (message.redacted) {
                    return Row(
                      key: Key('message-redacted-${message.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: KiteSpacing.xs),
                        Text(
                          'Message deleted',
                          style: KiteTypography.body.copyWith(
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    );
                  }
                  return Text(
                    message.body,
                    key: Key('message-body-${message.id}'),
                    style: KiteTypography.body.copyWith(
                      color: colors.onSurface,
                    ),
                  );
                },
              ),
              SignalBuilder(
                builder: (context) {
                  final reactions = message.reactions.entries.toList(
                    growable: false,
                  );
                  if (reactions.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: KiteSpacing.xs),
                    child: Wrap(
                      key: Key('message-reactions-${message.id}'),
                      spacing: KiteSpacing.xs,
                      runSpacing: KiteSpacing.xs,
                      children: <Widget>[
                        for (final reaction in reactions)
                          _ReactionPill(
                            message: message,
                            emoji: reaction.key,
                            reactors: reaction.value,
                          ),
                      ],
                    ),
                  );
                },
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
                  SignalBuilder(
                    builder: (context) => message.edited
                        ? Text(
                            ' · edited',
                            key: Key('edited-${message.id}'),
                            style: KiteTypography.metadata.copyWith(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          )
                        : const SizedBox.shrink(),
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

class _MessageReplyPreview extends StatelessWidget {
  const _MessageReplyPreview({required this.message});

  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: Key('reply-preview-${message.id}'),
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 460),
      padding: const EdgeInsets.only(left: KiteSpacing.xs),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.primary, width: KiteStroke.emphasis),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message.replyToSender ?? 'Message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KiteTypography.metadata.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            message.replyToBody ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KiteTypography.metadata.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.message,
    required this.emoji,
    required this.reactors,
  });

  final TimelineMessage message;
  final String emoji;
  final List<String> reactors;

  Future<void> _showReactors(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.kiteColors.canvas,
      constraints: const BoxConstraints(maxWidth: 440),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
      ),
      builder: (sheetContext) =>
          _ReactionDetailsSheet(emoji: emoji, reactors: reactors),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = reactors.contains('You');
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$emoji reaction, ${reactors.length} ${reactors.length == 1 ? 'person' : 'people'}',
      child: InkWell(
        key: Key('reaction-$emoji-${message.id}'),
        onTap: () => _showReactors(context),
        borderRadius: BorderRadius.circular(KiteRadii.pill),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(KiteRadii.pill),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: 0.42)
                  : colors.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiteSpacing.sm,
              vertical: KiteSpacing.xxs,
            ),
            child: Text(
              '$emoji  ${reactors.length}',
              style: KiteTypography.metadata.copyWith(
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionDetailsSheet extends StatelessWidget {
  const _ReactionDetailsSheet({required this.emoji, required this.reactors});

  final String emoji;
  final List<String> reactors;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('reaction-details-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.sm,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: KiteSpacing.lg),
          Text(
            '$emoji  ${reactors.length}',
            style: KiteTypography.title.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KiteSpacing.sm),
          for (final reactor in reactors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KiteSpacing.xs),
              child: Row(
                children: <Widget>[
                  _MessageAvatar(sender: reactor),
                  const SizedBox(width: KiteSpacing.sm),
                  Text(
                    reactor,
                    style: KiteTypography.body.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickReactionRow extends StatelessWidget {
  const _QuickReactionRow({required this.message});

  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const Key('quick-reaction-row'),
      children: <Widget>[
        for (
          var index = 0;
          index < _quickReactions.length;
          index++
        ) ...<Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: 'React with ${_quickReactions[index]}',
              child: InkWell(
                key: Key('quick-reaction-$index'),
                onTap: () {
                  timelineController.toggleReaction(
                    message,
                    _quickReactions[index],
                  );
                  Navigator.of(context).pop();
                },
                borderRadius: BorderRadius.circular(KiteRadii.pill),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      _quickReactions[index],
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (index != _quickReactions.length - 1)
            const SizedBox(width: KiteSpacing.xxs),
        ],
        const SizedBox(width: KiteSpacing.xxs),
        Tooltip(
          message: 'More reactions',
          child: InkWell(
            key: const Key('message-action-more-reactions'),
            onTap: () =>
                Navigator.of(context).pop(_MessageAction.reactionPicker),
            borderRadius: BorderRadius.circular(KiteRadii.pill),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.add_rounded, color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionPickerSheet extends StatelessWidget {
  const _ReactionPickerSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('reaction-picker-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.sm,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: KiteSpacing.lg),
          Text(
            'Choose a reaction',
            style: KiteTypography.title.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KiteSpacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reactionPickerEmoji.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: KiteSpacing.xs,
              crossAxisSpacing: KiteSpacing.xs,
            ),
            itemBuilder: (context, index) {
              final emoji = _reactionPickerEmoji[index];
              return InkWell(
                key: Key('reaction-picker-$index'),
                onTap: () => Navigator.of(context).pop(emoji),
                borderRadius: BorderRadius.circular(KiteRadii.md),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 25)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({required this.message});

  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('message-action-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.sm,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outlineVariant,
              borderRadius: BorderRadius.circular(KiteRadii.pill),
            ),
          ),
          const SizedBox(height: KiteSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KiteTypography.body.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: KiteSpacing.sm),
          if (!message.redacted) ...<Widget>[
            _QuickReactionRow(message: message),
            const SizedBox(height: KiteSpacing.sm),
            _MessageActionButton(
              key: const Key('message-action-reply'),
              icon: Icons.reply_rounded,
              label: 'Reply',
              onTap: () => Navigator.of(context).pop(_MessageAction.reply),
            ),
            _MessageActionButton(
              key: const Key('message-action-copy'),
              icon: Icons.content_copy_rounded,
              label: 'Copy text',
              onTap: () => Navigator.of(context).pop(_MessageAction.copy),
            ),
            _MessageActionButton(
              key: const Key('message-action-forward'),
              icon: Icons.forward_to_inbox_rounded,
              label: 'Forward',
              onTap: () => Navigator.of(context).pop(_MessageAction.forward),
            ),
            if (!message.mine)
              _MessageActionButton(
                key: const Key('message-action-report'),
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: () => Navigator.of(context).pop(_MessageAction.report),
              ),
            if (message.mine)
              _MessageActionButton(
                key: const Key('message-action-edit'),
                icon: Icons.edit_outlined,
                label: 'Edit message',
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
            if (message.mine)
              _MessageActionButton(
                key: const Key('message-action-delete'),
                icon: Icons.delete_outline_rounded,
                label: 'Delete message',
                destructive: true,
                onTap: () => Navigator.of(context).pop(_MessageAction.redact),
              ),
          ],
        ],
      ),
    );
  }
}

class _ForwardMessageSheet extends StatefulWidget {
  const _ForwardMessageSheet({
    required this.currentRoomId,
    required this.message,
  });

  final String currentRoomId;
  final TimelineMessage message;

  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final Set<String> _selectedRoomIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalizedQuery = _query.trim().toLowerCase();
    final rooms = BenchmarkFixture.rooms
        .where((room) => room.id != widget.currentRoomId)
        .where(
          (room) =>
              normalizedQuery.isEmpty ||
              room.name.toLowerCase().contains(normalizedQuery) ||
              room.subtitle.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
    return SafeArea(
      top: false,
      child: SizedBox(
        key: const Key('forward-message-sheet'),
        height: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.lg,
            KiteSpacing.sm,
            KiteSpacing.lg,
            KiteSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(KiteRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: KiteSpacing.lg),
              Text(
                'Forward message',
                style: KiteTypography.title.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: KiteSpacing.xs),
              Text(
                widget.message.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: KiteTypography.body.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KiteSpacing.md),
              TextField(
                key: const Key('forward-room-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search rooms',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: context.kiteColors.field,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                    vertical: KiteSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(KiteRadii.lg),
                  ),
                ),
              ),
              const SizedBox(height: KiteSpacing.sm),
              Expanded(
                child: ListView.builder(
                  key: const Key('forward-room-list'),
                  itemCount: rooms.length,
                  itemExtent: 56,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final selected = _selectedRoomIds.contains(room.id);
                    return InkWell(
                      key: Key('forward-room-${room.id}'),
                      onTap: () {
                        setState(() {
                          if (!_selectedRoomIds.add(room.id)) {
                            _selectedRoomIds.remove(room.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(KiteRadii.md),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 17,
                            child: Text(room.name.characters.first),
                          ),
                          const SizedBox(width: KiteSpacing.sm),
                          Expanded(
                            child: Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KiteTypography.body.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Checkbox(
                            value: selected,
                            onChanged: (_) {
                              setState(() {
                                if (!_selectedRoomIds.add(room.id)) {
                                  _selectedRoomIds.remove(room.id);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: KiteSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('forward-message-confirm'),
                  onPressed: _selectedRoomIds.isEmpty
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop(_selectedRoomIds.toList(growable: false)),
                  child: Text(
                    _selectedRoomIds.isEmpty
                        ? 'Select rooms'
                        : 'Forward to ${_selectedRoomIds.length}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportMessageSheet extends StatelessWidget {
  const _ReportMessageSheet({required this.message});

  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('report-message-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.sm,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: KiteSpacing.lg),
          Text(
            'Report message',
            style: KiteTypography.title.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KiteSpacing.xs),
          Text(
            message.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: KiteTypography.body.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: KiteSpacing.sm),
          for (var index = 0; index < _reportReasons.length; index++)
            _MessageActionButton(
              key: Key('report-reason-$index'),
              icon: index == _reportReasons.length - 1
                  ? Icons.more_horiz_rounded
                  : Icons.flag_outlined,
              label: _reportReasons[index],
              onTap: () => Navigator.of(context).pop(_reportReasons[index]),
            ),
        ],
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = destructive ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KiteRadii.md),
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            SizedBox(width: 44, child: Icon(icon, size: 21, color: foreground)),
            const SizedBox(width: KiteSpacing.xs),
            Text(
              label,
              style: KiteTypography.body.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteMessageDialog extends StatelessWidget {
  const _DeleteMessageDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      key: const Key('delete-message-dialog'),
      backgroundColor: context.kiteColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KiteRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(KiteSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Delete message?',
                style: KiteTypography.title.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: KiteSpacing.sm),
              Text(
                'This removes the message for everyone in the room. This action cannot be undone.',
                style: KiteTypography.body.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KiteSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: const Key('delete-message-cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  FilledButton(
                    key: const Key('delete-message-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
  const _Composer({super.key});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  _ComposerMode? _mode;
  String? _contextRoomId;
  TimelineMessage? _contextMessage;
  String _draftBeforeEdit = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void beginReply(String roomId, TimelineMessage message) {
    if (_mode == _ComposerMode.edit) {
      _controller.text = _draftBeforeEdit;
    }
    setState(() {
      _mode = _ComposerMode.reply;
      _contextRoomId = roomId;
      _contextMessage = message;
    });
    _focusNode.requestFocus();
  }

  void beginEdit(String roomId, TimelineMessage message) {
    if (!message.mine) return;
    if (_mode != _ComposerMode.edit) {
      _draftBeforeEdit = _controller.text;
    }
    _controller.value = TextEditingValue(
      text: message.body,
      selection: TextSelection.collapsed(offset: message.body.length),
    );
    setState(() {
      _mode = _ComposerMode.edit;
      _contextRoomId = roomId;
      _contextMessage = message;
    });
    _focusNode.requestFocus();
  }

  void _clearContext({required bool restoreEditDraft}) {
    final wasEditing = _mode == _ComposerMode.edit;
    if (restoreEditDraft && wasEditing) {
      _controller.value = TextEditingValue(
        text: _draftBeforeEdit,
        selection: TextSelection.collapsed(offset: _draftBeforeEdit.length),
      );
    }
    setState(() {
      _mode = null;
      _contextRoomId = null;
      _contextMessage = null;
      if (wasEditing) _draftBeforeEdit = '';
    });
  }

  void _send() {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    final roomId = selectedRoomId.value;
    final contextMessage = _contextRoomId == roomId ? _contextMessage : null;
    if (_mode == _ComposerMode.edit && contextMessage != null) {
      timelineController.editText(contextMessage, body);
      _clearContext(restoreEditDraft: true);
    } else {
      timelineController.sendText(
        roomId,
        body,
        replyTo: _mode == _ComposerMode.reply ? contextMessage : null,
      );
      _controller.clear();
      if (_mode != null) _clearContext(restoreEditDraft: false);
    }
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SignalBuilder(
      builder: (context) {
        final roomId = selectedRoomId.value;
        final activeMessage = _contextRoomId == roomId ? _contextMessage : null;
        final activeMode = activeMessage == null ? null : _mode;
        return AnimatedSize(
          key: const Key('composer'),
          alignment: Alignment.bottomCenter,
          duration: KiteMotion.resolve(context, KiteMotion.standard),
          curve: KiteMotion.standardCurve,
          child: ColoredBox(
            color: context.kiteColors.canvas,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (activeMessage != null && activeMode != null)
                  _ComposerContextBar(
                    mode: activeMode,
                    message: activeMessage,
                    onClose: () => _clearContext(restoreEditDraft: true),
                  ),
                SizedBox(
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
                            decoration: InputDecoration(
                              hintText: activeMode == _ComposerMode.edit
                                  ? 'Edit message…'
                                  : 'Message…',
                              isDense: true,
                              filled: true,
                              fillColor: context.kiteColors.field,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: KiteSpacing.md,
                                vertical: KiteSpacing.sm,
                              ),
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(
                                  KiteRadii.lg,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(
                                  KiteRadii.lg,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: colors.primary.withValues(alpha: 0.42),
                                  width: KiteStroke.emphasis,
                                ),
                                borderRadius: BorderRadius.circular(
                                  KiteRadii.lg,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: KiteSpacing.xs),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            final enabled = value.text.trim().isNotEmpty;
                            final editing = activeMode == _ComposerMode.edit;
                            return IconButton.filled(
                              key: const Key('composer-send'),
                              tooltip: editing ? 'Save edit' : 'Send message',
                              onPressed: enabled ? _send : null,
                              style: IconButton.styleFrom(
                                minimumSize: const Size.square(44),
                                backgroundColor: enabled
                                    ? colors.primary
                                    : colors.surfaceContainerHighest,
                                foregroundColor: enabled
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                                disabledBackgroundColor:
                                    colors.surfaceContainerHighest,
                                disabledForegroundColor:
                                    colors.onSurfaceVariant,
                              ),
                              icon: Icon(
                                editing
                                    ? Icons.check_rounded
                                    : Icons.arrow_upward_rounded,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComposerContextBar extends StatelessWidget {
  const _ComposerContextBar({
    required this.mode,
    required this.message,
    required this.onClose,
  });

  final _ComposerMode mode;
  final TimelineMessage message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editing = mode == _ComposerMode.edit;
    return Container(
      key: const Key('composer-context'),
      height: 52,
      margin: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        KiteSpacing.xs,
        KiteSpacing.md,
        0,
      ),
      padding: const EdgeInsets.only(left: KiteSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(KiteRadii.md),
        border: Border(
          left: BorderSide(color: colors.primary, width: KiteStroke.emphasis),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            editing ? Icons.edit_outlined : Icons.reply_rounded,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: KiteSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  editing ? 'Editing message' : 'Replying to ${message.sender}',
                  key: const Key('composer-context-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KiteTypography.metadata.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SignalBuilder(
                  builder: (context) => Text(
                    message.body,
                    key: const Key('composer-context-preview'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KiteTypography.metadata.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('composer-context-close'),
            tooltip: editing ? 'Cancel edit' : 'Cancel reply',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}
