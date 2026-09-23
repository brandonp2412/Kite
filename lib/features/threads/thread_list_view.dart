import 'package:flutter/material.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/l10n/kite_local_formats.dart';
import 'package:signals/signals_flutter.dart';

class ThreadListRoute extends PageRouteBuilder<void> {
  ThreadListRoute({required String roomId, required bool reduceMotion})
    : super(
        transitionDuration: reduceMotion ? Duration.zero : KiteMotion.standard,
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : KiteMotion.standard,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ThreadListView(roomId: roomId),
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
}

class ThreadListView extends StatefulWidget {
  const ThreadListView({super.key, required this.roomId});

  final String roomId;

  @override
  State<ThreadListView> createState() => _ThreadListViewState();
}

class _ThreadListViewState extends State<ThreadListView> {
  static const int _pageSize = 4;
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = _pageSize;

  List<TimelineMessage> _threadParents(List<TimelineMessage> messages) {
    return messages
        .where((message) => threadController.hasThread(message.id))
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  void _showMore(int totalCount) {
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(0, totalCount);
    });
  }

  Future<void> _openThread(BuildContext context, TimelineMessage parent) async {
    final anchor = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    await Navigator.of(context).push(
      ThreadRoute(
        roomId: widget.roomId,
        parent: parent,
        reduceMotion: KiteMotion.prefersReducedMotion(context),
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = anchor
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() > 0.5) position.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final room = BenchmarkFixture.room(widget.roomId);
    return Scaffold(
      backgroundColor: context.kiteColors.canvas,
      body: SafeArea(
        child: Column(
          key: const Key('thread-list-panel'),
          children: <Widget>[
            SizedBox(
              key: const Key('thread-list-header'),
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.xs),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      key: const Key('thread-list-back'),
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
                            'Threads',
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
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final messages = timelineController
                      .messagesFor(widget.roomId)
                      .value;
                  final parents = _threadParents(messages);
                  if (parents.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(KiteSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.forum_outlined,
                              size: 34,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: KiteSpacing.sm),
                            Text(
                              'No threads yet',
                              style: KiteTypography.title.copyWith(
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: KiteSpacing.xs),
                            Text(
                              'Replies started in a thread will appear here.',
                              textAlign: TextAlign.center,
                              style: KiteTypography.body.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final visibleCount = _visibleCount.clamp(0, parents.length);
                  final hasMore = visibleCount < parents.length;
                  return ListView.builder(
                    key: const Key('thread-list'),
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      KiteSpacing.md,
                      KiteSpacing.sm,
                      KiteSpacing.md,
                      KiteSpacing.md,
                    ),
                    itemCount: visibleCount + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == visibleCount) {
                        return SizedBox(
                          key: const Key('thread-list-pagination'),
                          height: 56,
                          child: Center(
                            child: TextButton.icon(
                              key: const Key('thread-list-load-more'),
                              onPressed: () => _showMore(parents.length),
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text(
                                'Show more threads',
                                style: KiteTypography.metadata.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final parent = parents[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: KiteSpacing.xs),
                        child: _ThreadListRow(
                          roomId: widget.roomId,
                          parent: parent,
                          onTap: () => _openThread(context, parent),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadListRow extends StatelessWidget {
  const _ThreadListRow({
    required this.roomId,
    required this.parent,
    required this.onTap,
  });

  final String roomId;
  final TimelineMessage parent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SignalBuilder(
      builder: (context) {
        final replies = threadController
            .repliesFor(roomId: roomId, parent: parent)
            .value;
        final unread = threadController
            .unreadCountFor(roomId: roomId, parent: parent)
            .value;
        final latest = replies.isEmpty ? null : replies.last;
        final replyCount = replies.length;
        return Semantics(
          button: true,
          label:
              '${parent.sender}, ${parent.body}, ${KiteLocalFormats.decimal(context, replyCount)} ${replyCount == 1 ? 'reply' : 'replies'}${unread > 0 ? ', ${KiteLocalFormats.decimal(context, unread)} unread' : ''}',
          child: InkWell(
            key: Key('thread-list-row-${parent.id}'),
            onTap: onTap,
            child: Container(
              height: 112,
              padding: const EdgeInsets.symmetric(
                horizontal: KiteSpacing.md,
                vertical: KiteSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.72),
                    width: KiteStroke.hairline,
                  ),
                ),
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
                        const SizedBox(height: KiteSpacing.xxs),
                        Text(
                          parent.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KiteTypography.body.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.forum_outlined,
                              size: 16,
                              color: colors.primary,
                            ),
                            const SizedBox(width: KiteSpacing.xs),
                            Text(
                              '${KiteLocalFormats.decimal(context, replyCount)} ${replyCount == 1 ? 'reply' : 'replies'}',
                              style: KiteTypography.metadata.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: KiteSpacing.sm),
                            Expanded(
                              child: Text(
                                latest == null
                                    ? 'No replies yet'
                                    : '${latest.sender}: ${latest.body}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KiteTypography.metadata.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (unread > 0) ...<Widget>[
                              const SizedBox(width: KiteSpacing.sm),
                              Container(
                                key: Key('thread-list-unread-${parent.id}'),
                                constraints: const BoxConstraints(minWidth: 20),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KiteSpacing.xs,
                                  vertical: KiteSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(
                                    KiteRadii.pill,
                                  ),
                                ),
                                child: Text(
                                  '$unread',
                                  textAlign: TextAlign.center,
                                  style: KiteTypography.metadata.copyWith(
                                    color: colors.onPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
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
