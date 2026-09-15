import 'package:flutter/material.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_media_viewer.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals_flutter.dart';

class ThreadRoute extends PageRouteBuilder<void> {
  ThreadRoute({
    required String roomId,
    required TimelineMessage parent,
    required bool reduceMotion,
    String? focusedReplyId,
  }) : super(
         transitionDuration: reduceMotion ? Duration.zero : KiteMotion.standard,
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : KiteMotion.standard,
         pageBuilder: (context, animation, secondaryAnimation) => ThreadView(
           roomId: roomId,
           parent: parent,
           focusedReplyId: focusedReplyId,
         ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (reduceMotion) return child;
           final curved = CurvedAnimation(
             parent: animation,
             curve: KiteMotion.emphasizedCurve,
             reverseCurve: KiteMotion.standardCurve,
           );
           return SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.06, 0),
               end: Offset.zero,
             ).animate(curved),
             child: child,
           );
         },
       );

  factory ThreadRoute.fromDestination({
    required AppDestination destination,
    required TimelineMessage parent,
    required bool reduceMotion,
  }) {
    if (destination.kind != AppDestinationKind.thread ||
        destination.threadRootEventId != parent.id ||
        destination.roomId.isEmpty ||
        destination.eventId == null) {
      throw ArgumentError.value(
        destination,
        'destination',
        'Thread destination must target this parent and a reply event',
      );
    }
    return ThreadRoute(
      roomId: destination.roomId,
      parent: parent,
      reduceMotion: reduceMotion,
      focusedReplyId: destination.eventId,
    );
  }
}

class ThreadView extends StatefulWidget {
  const ThreadView({
    super.key,
    required this.roomId,
    required this.parent,
    this.focusedReplyId,
  });

  final String roomId;
  final TimelineMessage parent;
  final String? focusedReplyId;

  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> {
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final focusedReplyId = widget.focusedReplyId;
    if (focusedReplyId != null) {
      threadController.focusReply(
        roomId: widget.roomId,
        parent: widget.parent,
        replyId: focusedReplyId,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      threadController.markRead(roomId: widget.roomId, parent: widget.parent);
    });
  }

  @override
  void dispose() {
    final focusedReplyId = widget.focusedReplyId;
    if (focusedReplyId != null) {
      threadController.clearFocus(
        roomId: widget.roomId,
        parent: widget.parent,
        onlyIfReplyId: focusedReplyId,
      );
    }
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _send() {
    final body = _composerController.text.trim();
    if (body.isEmpty) return;
    threadController.sendReply(
      roomId: widget.roomId,
      parent: widget.parent,
      rawBody: body,
    );
    _composerController.clear();
    _composerFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final room = BenchmarkFixture.room(widget.roomId);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: context.kiteColors.canvas,
      body: SafeArea(
        child: Column(
          key: const Key('thread-panel'),
          children: <Widget>[
            SizedBox(
              key: const Key('thread-header'),
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.xs),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      key: const Key('thread-back'),
                      tooltip: 'Back to room',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Thread',
                            style: KiteTypography.title.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KiteTypography.metadata.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ThreadSubscriptionButton(
                      roomId: widget.roomId,
                      parent: widget.parent,
                    ),
                    const SizedBox(width: KiteSpacing.xxs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KiteSpacing.sm,
                        vertical: KiteSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(KiteRadii.pill),
                      ),
                      child: SignalBuilder(
                        builder: (context) {
                          final count = threadController
                              .repliesFor(
                                roomId: widget.roomId,
                                parent: widget.parent,
                              )
                              .value
                              .length;
                          return Text(
                            '$count ${count == 1 ? 'reply' : 'replies'}',
                            key: const Key('thread-reply-count'),
                            style: KiteTypography.metadata.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _ThreadRoot(parent: widget.parent),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(child: Divider(color: colors.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KiteSpacing.sm,
                    ),
                    child: Text(
                      'THREAD',
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: colors.outlineVariant)),
                ],
              ),
            ),
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final replies = threadController
                      .repliesFor(roomId: widget.roomId, parent: widget.parent)
                      .value;
                  final hasMore = threadController
                      .hasMoreFor(roomId: widget.roomId, parent: widget.parent)
                      .value;
                  final loading = threadController
                      .isLoadingOlderFor(
                        roomId: widget.roomId,
                        parent: widget.parent,
                      )
                      .value;
                  final focusSignal = threadController.focusedReplyIdFor(
                    roomId: widget.roomId,
                    parent: widget.parent,
                  );
                  return Stack(
                    children: <Widget>[
                      ListView.builder(
                        key: const Key('thread-reply-list'),
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(
                          KiteSpacing.md,
                          52,
                          KiteSpacing.md,
                          KiteSpacing.sm,
                        ),
                        itemCount: replies.length,
                        itemBuilder: (context, index) {
                          final reply = replies[replies.length - 1 - index];
                          return _ThreadReplyRow(
                            key: ValueKey<String>(reply.id),
                            roomId: widget.roomId,
                            parent: widget.parent,
                            reply: reply,
                            focusSignal: focusSignal,
                          );
                        },
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: SizedBox(
                          key: const Key('thread-pagination'),
                          height: 44,
                          child: Center(
                            child: hasMore
                                ? TextButton.icon(
                                    key: const Key('thread-load-older'),
                                    onPressed: loading
                                        ? null
                                        : () => threadController.loadOlder(
                                            roomId: widget.roomId,
                                            parent: widget.parent,
                                          ),
                                    icon: loading
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.history_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      loading
                                          ? 'Loading…'
                                          : 'Load older replies',
                                    ),
                                  )
                                : Text(
                                    'Start of thread',
                                    style: KiteTypography.metadata.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              key: const Key('thread-composer'),
              height: 76,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KiteSpacing.md,
                  KiteSpacing.xs,
                  KiteSpacing.md,
                  KiteSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const Key('thread-composer-field'),
                        controller: _composerController,
                        focusNode: _composerFocusNode,
                        minLines: 1,
                        maxLines: 2,
                        style: KiteTypography.body,
                        decoration: InputDecoration(
                          hintText: 'Reply in thread…',
                          isDense: true,
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
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(KiteRadii.lg),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: colors.primary.withValues(alpha: 0.42),
                              width: KiteStroke.emphasis,
                            ),
                            borderRadius: BorderRadius.circular(KiteRadii.lg),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _composerController,
                      builder: (context, value, child) {
                        final enabled = value.text.trim().isNotEmpty;
                        return IconButton.filled(
                          key: const Key('thread-composer-send'),
                          tooltip: 'Send thread reply',
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
          ],
        ),
      ),
    );
  }
}

class _ThreadSubscriptionButton extends StatelessWidget {
  const _ThreadSubscriptionButton({required this.roomId, required this.parent});

  final String roomId;
  final TimelineMessage parent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: SignalBuilder(
        builder: (context) {
          final following = threadController
              .isFollowingFor(roomId: roomId, parent: parent)
              .value;
          final updating = threadController
              .isUpdatingSubscriptionFor(roomId: roomId, parent: parent)
              .value;
          final failed = threadController
              .subscriptionFailedFor(roomId: roomId, parent: parent)
              .value;
          final tooltip = failed
              ? 'Retry thread notifications'
              : following
              ? 'Unfollow thread'
              : 'Follow thread';
          return IconButton(
            key: const Key('thread-subscription-toggle'),
            tooltip: tooltip,
            onPressed: updating
                ? null
                : () => threadController.toggleFollowing(
                    roomId: roomId,
                    parent: parent,
                  ),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              foregroundColor: failed ? colors.error : colors.onSurfaceVariant,
            ),
            icon: updating
                ? SizedBox.square(
                    key: const Key('thread-subscription-progress'),
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : Icon(
                    failed
                        ? Icons.notifications_active_rounded
                        : following
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    key: Key(
                      following
                          ? 'thread-subscription-following'
                          : 'thread-subscription-not-following',
                    ),
                    semanticLabel: tooltip,
                    size: 21,
                  ),
          );
        },
      ),
    );
  }
}

class _ThreadRoot extends StatelessWidget {
  const _ThreadRoot({required this.parent});

  final TimelineMessage parent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('thread-root'),
      margin: const EdgeInsets.all(KiteSpacing.md),
      padding: const EdgeInsets.all(KiteSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(KiteRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            child: Text(
              parent.sender.characters.first.toUpperCase(),
              style: KiteTypography.metadata.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: KiteSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        parent.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      parent.timeLabel,
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KiteSpacing.xs),
                Text(
                  parent.body,
                  style: KiteTypography.body.copyWith(color: colors.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadReplyRow extends StatelessWidget {
  const _ThreadReplyRow({
    super.key,
    required this.roomId,
    required this.parent,
    required this.reply,
    required this.focusSignal,
  });

  final String roomId;
  final TimelineMessage parent;
  final ThreadReply reply;
  final Signal<String?> focusSignal;

  void _openMedia(BuildContext context) {
    final model = ThreadMediaViewerModel.fromReplies(
      roomId: roomId,
      parent: parent,
      replies: threadController
          .repliesFor(roomId: roomId, parent: parent)
          .value,
      initialReplyId: reply.id,
    );
    Navigator.of(context).push(
      MediaViewerRoute(
        items: model.items,
        initialIndex: model.initialIndex,
        onSave: model.onSave,
        onShare: model.onShare,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mine = reply.mine;
    return SignalBuilder(
      builder: (context) {
        final focused = focusSignal.value == reply.id;
        return Semantics(
          focused: focused,
          label: focused ? 'Focused thread reply from ${reply.sender}' : null,
          child: DecoratedBox(
            key: focused ? Key('thread-focused-${reply.id}') : null,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: focused ? colors.primary : Colors.transparent,
                ),
              ),
            ),
            child: Padding(
              key: Key('thread-reply-${reply.id}'),
              padding: const EdgeInsets.symmetric(vertical: KiteSpacing.xs),
              child: Row(
                mainAxisAlignment: mine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (!mine) ...<Widget>[
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                      child: Text(
                        reply.sender.characters.first.toUpperCase(),
                        style: KiteTypography.metadata.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                  ],
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      padding: const EdgeInsets.fromLTRB(
                        KiteSpacing.sm,
                        KiteSpacing.xs,
                        KiteSpacing.xs,
                        KiteSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: mine
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(KiteRadii.md),
                          topRight: const Radius.circular(KiteRadii.md),
                          bottomLeft: Radius.circular(
                            mine ? KiteRadii.md : KiteRadii.sm,
                          ),
                          bottomRight: Radius.circular(
                            mine ? KiteRadii.sm : KiteRadii.md,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (!mine) ...<Widget>[
                            Text(
                              reply.sender,
                              style: KiteTypography.metadata.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: KiteSpacing.xxs),
                          ],
                          if (reply.attachment
                              case final attachment?) ...<Widget>[
                            TimelineAttachmentCard(
                              messageId: 'thread-${reply.id}',
                              attachment: attachment,
                              heroTag:
                                  attachment.kind == TimelineAttachmentKind.file
                                  ? null
                                  : threadMediaHeroTag(parent, reply),
                              onTap:
                                  attachment.kind == TimelineAttachmentKind.file
                                  ? null
                                  : () => _openMedia(context),
                            ),
                            if (reply.body.isNotEmpty)
                              const SizedBox(height: KiteSpacing.xs),
                          ],
                          if (reply.body.isNotEmpty)
                            Text(
                              reply.body,
                              style: KiteTypography.body.copyWith(
                                color: colors.onSurface,
                              ),
                            ),
                          const SizedBox(height: KiteSpacing.xxs),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                reply.timeLabel,
                                style: KiteTypography.metadata.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              if (mine) ...<Widget>[
                                const SizedBox(width: KiteSpacing.xxs),
                                SignalBuilder(
                                  builder: (context) {
                                    final state = reply.sendState.value;
                                    return SizedBox(
                                      key: Key('thread-send-state-${reply.id}'),
                                      width: 20,
                                      height: 20,
                                      child: state == TimelineSendState.failed
                                          ? Tooltip(
                                              message: 'Retry sending',
                                              child: InkResponse(
                                                key: Key(
                                                  'thread-retry-${reply.id}',
                                                ),
                                                radius: 18,
                                                containedInkWell: true,
                                                onTap: () =>
                                                    threadController.retryReply(
                                                      roomId: roomId,
                                                      parent: parent,
                                                      reply: reply,
                                                    ),
                                                child: Icon(
                                                  Icons.error_rounded,
                                                  semanticLabel: 'Thread reply failed. Retry sending',
                                                  size: 14,
                                                  color: colors.error,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              state == TimelineSendState.sending
                                                  ? Icons.schedule_rounded
                                                  : Icons.done_rounded,
                                              size: 14,
                                              color: colors.onSurfaceVariant,
                                            ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
