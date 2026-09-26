import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:signals/signals_flutter.dart';

enum RoomContentTab { media, files, links }

@immutable
final class RoomContentLink {
  const RoomContentLink({
    required this.messageId,
    required this.url,
    required this.sender,
    required this.timeLabel,
  });

  final String messageId;
  final Uri url;
  final String sender;
  final String timeLabel;
}

List<RoomContentLink> roomContentLinks(Iterable<TimelineMessage> messages) {
  final links = <RoomContentLink>[];
  final seen = <String>{};
  final pattern = RegExp(r'https?://[^\s<>()]+', caseSensitive: false);
  for (final message in messages) {
    if (message.redacted) continue;
    for (final match in pattern.allMatches(message.body)) {
      final raw = match.group(0);
      if (raw == null) continue;
      final normalized = raw.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
      final uri = Uri.tryParse(normalized);
      if (uri == null ||
          !uri.hasAuthority ||
          !seen.add('$normalized\u0000${message.id}')) {
        continue;
      }
      links.add(
        RoomContentLink(
          messageId: message.id,
          url: uri,
          sender: message.sender,
          timeLabel: message.timeLabel,
        ),
      );
    }
  }
  return List<RoomContentLink>.unmodifiable(links.reversed);
}

class RoomContentGallery extends StatefulWidget {
  const RoomContentGallery({
    super.key,
    required this.roomId,
    required this.messages,
    this.mediaResolver = const DeterministicTimelineMediaResolver(),
    this.mediaActionPort = const DeterministicTimelineMediaActionPort(),
    this.onOpenLink,
    this.onLoadOlder,
  });

  final String roomId;
  final ReadonlySignal<List<TimelineMessage>> messages;
  final TimelineMediaResolver mediaResolver;
  final TimelineMediaActionPort mediaActionPort;
  final ValueChanged<Uri>? onOpenLink;
  final Future<void> Function()? onLoadOlder;

  @override
  State<RoomContentGallery> createState() => _RoomContentGalleryState();
}

class _RoomContentGalleryState extends State<RoomContentGallery> {
  bool _loadingOlder = false;
  bool _historyExhausted = false;

  @override
  void initState() {
    super.initState();
    if (widget.onLoadOlder != null &&
        !_hasSharedContent(widget.messages.peek())) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadOlder(maxPages: 8));
      });
    }
  }

  bool _hasSharedContent(List<TimelineMessage> messages) {
    for (final message in messages) {
      if (!message.redacted && message.attachment != null) return true;
    }
    return roomContentLinks(messages).isNotEmpty;
  }

  Future<void> _loadOlder({int maxPages = 8}) async {
    final loadOlder = widget.onLoadOlder;
    if (loadOlder == null || _loadingOlder || _historyExhausted) return;
    setState(() => _loadingOlder = true);
    try {
      for (var page = 0; page < maxPages && mounted; page += 1) {
        final before = widget.messages.peek().length;
        await loadOlder();
        if (!mounted) return;
        final after = widget.messages.peek().length;
        if (after <= before) {
          _historyExhausted = true;
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: RoomContentTab.values.length,
      child: Scaffold(
        key: const Key('room-content-gallery'),
        backgroundColor: context.kiteColors.canvas,
        appBar: AppBar(
          key: const Key('room-content-gallery-header'),
          title: const Text('Shared content'),
          actions: <Widget>[
            if (widget.onLoadOlder != null && !_historyExhausted)
              IconButton(
                key: const Key('room-content-load-older'),
                tooltip: 'Load older shared content',
                onPressed: _loadingOlder ? null : () => _loadOlder(),
                icon: const Icon(Icons.history_rounded),
              ),
          ],
          bottom: const TabBar(
            key: Key('room-content-tabs'),
            tabs: <Widget>[
              Tab(key: Key('room-content-tab-media'), text: 'Media'),
              Tab(key: Key('room-content-tab-files'), text: 'Files'),
              Tab(key: Key('room-content-tab-links'), text: 'Links'),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (_loadingOlder)
              const LinearProgressIndicator(
                key: Key('room-content-history-loading'),
              ),
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final current = widget.messages.value;
                  final mediaMessages = current
                      .where(
                        (message) =>
                            !message.redacted &&
                            message.attachment != null &&
                            message.attachment!.kind.isVisualMedia,
                      )
                      .toList(growable: false);
                  final fileMessages = current
                      .where(
                        (message) =>
                            !message.redacted &&
                            message.attachment != null &&
                            !message.attachment!.kind.isVisualMedia,
                      )
                      .toList(growable: false)
                      .reversed
                      .toList(growable: false);
                  final links = roomContentLinks(current);
                  return TabBarView(
                    key: const Key('room-content-tab-view'),
                    children: <Widget>[
                      _MediaGrid(
                        roomId: widget.roomId,
                        allMessages: current,
                        messages: mediaMessages.reversed.toList(
                          growable: false,
                        ),
                        mediaResolver: widget.mediaResolver,
                        mediaActionPort: widget.mediaActionPort,
                      ),
                      _FileList(messages: fileMessages),
                      _LinkList(links: links, onOpenLink: widget.onOpenLink),
                    ],
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

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.roomId,
    required this.allMessages,
    required this.messages,
    required this.mediaResolver,
    required this.mediaActionPort,
  });

  final String roomId;
  final List<TimelineMessage> allMessages;
  final List<TimelineMessage> messages;
  final TimelineMediaResolver mediaResolver;
  final TimelineMediaActionPort mediaActionPort;

  void _open(BuildContext context, TimelineMessage message) {
    final model = TimelineMediaViewerModel.fromMessages(
      roomId: roomId,
      messages: allMessages,
      initialMessageId: message.id,
      resolver: mediaResolver,
      actionPort: mediaActionPort,
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
    if (messages.isEmpty) {
      return const _EmptyState(
        key: Key('room-content-empty-media'),
        icon: Icons.photo_library_outlined,
        title: 'No media yet',
        detail: 'Photos and videos shared in this room will appear here.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 520 => 3,
          < 900 => 4,
          _ => 6,
        };
        return GridView.builder(
          key: const Key('room-content-media-grid'),
          padding: const EdgeInsets.all(KiteSpacing.sm),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: KiteSpacing.xs,
            mainAxisSpacing: KiteSpacing.xs,
            childAspectRatio: 1,
          ),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final thumbnail = mediaResolver.thumbnailFor(message);
            return Semantics(
              button: true,
              label: '${timelineMediaSemanticLabel(message)}, open media',
              child: Material(
                color: context.kiteColors.canvas,
                borderRadius: BorderRadius.circular(KiteRadii.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('room-content-media-${message.id}'),
                  onTap: () => _open(context, message),
                  child: Hero(
                    tag: timelineMediaHeroTag(message),
                    child: thumbnail(context),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.messages});

  final List<TimelineMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const _EmptyState(
        key: Key('room-content-empty-files'),
        icon: Icons.insert_drive_file_outlined,
        title: 'No files yet',
        detail:
            'Documents and other files shared in this room will appear here.',
      );
    }

    return ListView.separated(
      key: const Key('room-content-file-list'),
      padding: const EdgeInsets.symmetric(vertical: KiteSpacing.sm),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = messages[index];
        final attachment = message.attachment!;
        return ListTile(
          key: Key('room-content-file-${message.id}'),
          minLeadingWidth: 48,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KiteSpacing.lg,
            vertical: KiteSpacing.xs,
          ),
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(KiteRadii.sm),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Icon(switch (attachment.kind) {
                TimelineAttachmentKind.audio => Icons.graphic_eq_rounded,
                TimelineAttachmentKind.voice => Icons.mic_none_rounded,
                _ => Icons.insert_drive_file_outlined,
              }),
            ),
          ),
          title: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KiteTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${attachment.sizeLabel} · ${message.sender} · ${message.timeLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _LinkList extends StatelessWidget {
  const _LinkList({required this.links, required this.onOpenLink});

  final List<RoomContentLink> links;
  final ValueChanged<Uri>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const _EmptyState(
        key: Key('room-content-empty-links'),
        icon: Icons.link_rounded,
        title: 'No links yet',
        detail: 'Links shared in this room will appear here.',
      );
    }

    return ListView.separated(
      key: const Key('room-content-link-list'),
      padding: const EdgeInsets.symmetric(vertical: KiteSpacing.sm),
      itemCount: links.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final link = links[index];
        final host = link.url.host.isEmpty
            ? link.url.toString()
            : link.url.host;
        return ListTile(
          key: Key('room-content-link-${link.messageId}-$index'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KiteSpacing.lg,
            vertical: KiteSpacing.xs,
          ),
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(KiteRadii.sm),
            ),
            child: const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.link_rounded),
            ),
          ),
          title: Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KiteTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${link.url} · ${link.sender} · ${link.timeLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.open_in_new_rounded, size: 20),
          onTap: onOpenLink == null ? null : () => onOpenLink!(link.url),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(KiteSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 42, color: colors.onSurfaceVariant),
              const SizedBox(height: KiteSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: KiteSpacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: KiteTypography.body.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
