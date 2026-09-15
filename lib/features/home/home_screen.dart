import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/jitter_injector.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_details_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/home/spaces_screen.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/media/room_content_gallery.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/features/timeline/timeline_message_body.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:kite/l10n/kite_localizations.dart';
import 'package:signals/signals_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.benchmarkRooms,
    this.roomListStore,
    this.inviteStore,
  });

  final List<BenchmarkRoom>? benchmarkRooms;
  final RoomListStateStore? roomListStore;
  final RoomInviteStore? inviteStore;

  static const double sidebarWidth = 320;
  static const double tabletSidebarWidth = 300;
  static const double phoneBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < phoneBreakpoint;
    final rooms = benchmarkRooms ?? BenchmarkFixture.rooms;
    final roomEntries = deterministicRoomListEntries(rooms);

    if (isPhone) {
      return Scaffold(
        body: SafeArea(
          child: SizedBox.expand(
            key: const Key('sidebar'),
            child: _HomeSidebar(
              rooms: roomEntries,
              store: roomListStore,
              inviteStore: inviteStore,
              onRoomTap: (roomId) {
                selectRoom(roomId);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _CompactChatScreen(),
                  ),
                );
              },
            ),
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
            child: _HomeSidebar(
              rooms: roomEntries,
              store: roomListStore,
              inviteStore: inviteStore,
            ),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: RepaintBoundary(child: _ChatPanel())),
        ],
      ),
    );
  }
}

class _HomeSidebar extends StatefulWidget {
  const _HomeSidebar({
    required this.rooms,
    this.store,
    this.inviteStore,
    this.onRoomTap,
  });

  final List<RoomListEntry> rooms;
  final RoomListStateStore? store;
  final RoomInviteStore? inviteStore;
  final ValueChanged<String>? onRoomTap;

  @override
  State<_HomeSidebar> createState() => _HomeSidebarState();
}

class _HomeSidebarState extends State<_HomeSidebar> {
  late RoomListStateStore _ownedStore;
  late RoomInviteStore _ownedInviteStore;

  RoomListStateStore get store => widget.store ?? _ownedStore;
  RoomInviteStore get inviteStore => widget.inviteStore ?? _ownedInviteStore;

  @override
  void initState() {
    super.initState();
    _ownedStore = RoomListStateStore(widget.rooms);
    _ownedInviteStore = RoomInviteStore(deterministicRoomInvites);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _HomeHeader(store: store),
        _SpaceFilterBar(store: store),
        _RoomFilterBar(store: store),
        _InviteSection(store: inviteStore),
        Expanded(
          child: _RoomList(store: store, onRoomTap: widget.onRoomTap),
        ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.store});

  final RoomListStateStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.md,
          KiteSpacing.sm,
          KiteSpacing.sm,
          KiteSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            Semantics(
              image: true,
              label: 'Profile',
              child: CircleAvatar(
                key: const Key('home-profile'),
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_rounded,
                  size: 22,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: KiteSpacing.sm),
            Expanded(
              child: Text(
                AppLocalizations.of(context).chatsTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            IconButton(
              key: const Key('home-spaces'),
              tooltip: 'Spaces',
              onPressed: () => Navigator.of(context).push(
                SpacesRoute(
                  reduceMotion: KiteMotion.prefersReducedMotion(context),
                ),
              ),
              icon: const Icon(Icons.grid_view_rounded),
            ),
            IconButton(
              key: const Key('home-read-all'),
              tooltip: 'Mark all as read',
              onPressed: store.markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceFilterBar extends StatelessWidget {
  const _SpaceFilterBar({required this.store});

  final RoomListStateStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: SignalBuilder(
        builder: (context) {
          final selectedSpaceId = store.selectedSpaceId.value;
          return ListView.separated(
            key: const Key('space-filter-row'),
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
            scrollDirection: Axis.horizontal,
            itemCount: deterministicJoinedSpaces.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xs),
            itemBuilder: (context, index) {
              final space = index == 0
                  ? null
                  : deterministicJoinedSpaces[index - 1];
              final id = space?.id;
              final selected = selectedSpaceId == id;
              final label = space?.name ?? 'All';
              return ChoiceChip(
                key: Key('space-filter-${id ?? 'all'}'),
                selected: selected,
                showCheckmark: false,
                avatar: CircleAvatar(
                  radius: 12,
                  backgroundColor: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  child: Text(
                    space == null ? '•' : space.name.characters.first,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                label: Text(label),
                onSelected: (_) => store.selectSpace(id),
              );
            },
          );
        },
      ),
    );
  }
}

class _RoomFilterBar extends StatelessWidget {
  const _RoomFilterBar({required this.store});

  final RoomListStateStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: SignalBuilder(
        builder: (context) {
          final selected = store.selectedFilter.value;
          return ListView.separated(
            key: const Key('room-filter-row'),
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
            scrollDirection: Axis.horizontal,
            itemCount: RoomListFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xs),
            itemBuilder: (context, index) {
              final filter = RoomListFilter.values[index];
              return ChoiceChip(
                key: Key('room-filter-${filter.name}'),
                label: Text(filter.label),
                selected: selected == filter,
                showCheckmark: false,
                onSelected: (_) => store.selectFilter(filter),
              );
            },
          );
        },
      ),
    );
  }
}

class _InviteSection extends StatelessWidget {
  const _InviteSection({required this.store});

  final RoomInviteStore store;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final inviteIds = store.visibleInviteIds.value;
        if (inviteIds.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.md,
            KiteSpacing.xs,
            KiteSpacing.md,
            KiteSpacing.sm,
          ),
          child: Column(
            key: const Key('room-invites'),
            children: <Widget>[
              for (final inviteId in inviteIds)
                _InviteCard(
                  key: ValueKey<String>('invite-$inviteId'),
                  invite: store.invite(inviteId),
                  state: store.stateSignal(inviteId),
                  onAccept: () => store.accept(inviteId),
                  onDecline: () => store.decline(inviteId),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    super.key,
    required this.invite,
    required this.state,
    required this.onAccept,
    required this.onDecline,
  });

  final RoomInvite invite;
  final ReadonlySignal<RoomInviteActionState> state;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(KiteRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KiteSpacing.sm),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              child: Text(
                invite.roomName.characters.first,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: KiteSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    invite.roomName,
                    key: Key('invite-title-${invite.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${invite.inviterName} invited you · ${invite.memberCount} members',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (invite.description case final description?)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: KiteSpacing.xs),
            SignalBuilder(
              builder: (context) {
                final actionState = state.value;
                final pending =
                    actionState == RoomInviteActionState.accepting ||
                    actionState == RoomInviteActionState.declining;
                if (pending) {
                  return SizedBox.square(
                    key: Key('invite-progress-${invite.id}'),
                    dimension: 48,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      key: Key('invite-decline-${invite.id}'),
                      tooltip: 'Decline invite',
                      onPressed: onDecline,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    IconButton.filled(
                      key: Key('invite-accept-${invite.id}'),
                      tooltip: 'Accept invite',
                      onPressed: onAccept,
                      icon: const Icon(Icons.check_rounded),
                    ),
                  ],
                );
              },
            ),
          ],
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
  const _RoomList({required this.store, this.onRoomTap});

  final RoomListStateStore store;
  final ValueChanged<String>? onRoomTap;

  Future<void> _showMoveSectionSheet(BuildContext context, String roomId) {
    final currentSectionId = store.sectionIdFor(roomId);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        key: Key('room-options-sheet-$roomId'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.lg,
            0,
            KiteSpacing.lg,
            KiteSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Room options',
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: KiteSpacing.sm),
              SignalBuilder(
                builder: (context) {
                  final favourite = store.roomSignal(roomId).value.isFavourite;
                  return ListTile(
                    key: Key('room-favourite-toggle-$roomId'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 52,
                    leading: Icon(
                      favourite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: favourite
                          ? Theme.of(sheetContext).colorScheme.primary
                          : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      favourite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                    ),
                    onTap: () => store.toggleFavourite(roomId),
                  );
                },
              ),
              const Divider(height: KiteSpacing.lg),
              Text(
                'Move to section',
                style: Theme.of(sheetContext).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: KiteSpacing.xs),
              for (final section in store.sections)
                ListTile(
                  key: Key('room-section-move-$roomId-${section.id}'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 52,
                  leading: Icon(
                    section.id == currentSectionId
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: section.id == currentSectionId
                        ? Theme.of(sheetContext).colorScheme.primary
                        : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(section.name),
                  onTap: section.id == currentSectionId
                      ? null
                      : () {
                          store.moveRoomToSection(roomId, section.id);
                          Navigator.of(sheetContext).pop();
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomRow(BuildContext context, String roomId, double rowExtent) {
    return SizedBox(
      height: rowExtent,
      child: SignalBuilder(
        builder: (context) {
          final room = store.roomSignal(roomId).value;
          final selected = selectedRoomId.value == room.id;
          final unreadThreadCount = threadController
              .unreadThreadCountForRoom(room.id)
              .value;
          return _RoomListRow(
            key: ValueKey<String>(room.id),
            room: room,
            selected: selected,
            unreadThreadCount: unreadThreadCount,
            onLongPress: () => _showMoveSectionSheet(context, room.id),
            onTap: () {
              final handler = onRoomTap;
              if (handler != null) {
                handler(room.id);
              } else {
                selectRoom(room.id);
              }
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rowExtent = textScale > 1.3 ? 96.0 : 72.0;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: SignalBuilder(
        builder: (context) {
          final ids = store.visibleRoomIds.value;
          final sectionsVisible =
              store.selectedFilter.value == RoomListFilter.all &&
              store.selectedSpaceId.value == null;
          if (!sectionsVisible) {
            return ListView.builder(
              key: const Key('room-list'),
              itemCount: ids.length,
              itemExtent: rowExtent,
              itemBuilder: (context, index) =>
                  _roomRow(context, ids[index], rowExtent),
            );
          }

          store.sectionLayoutRevision.value;
          final collapsed = store.collapsedSectionIds.value;
          final items = <Object>[];
          for (final section in store.sections) {
            final sectionRoomIds = store.visibleRoomIdsForSection(section.id);
            if (sectionRoomIds.isEmpty) continue;
            items.add(section);
            if (!collapsed.contains(section.id)) items.addAll(sectionRoomIds);
          }
          return ListView.builder(
            key: const Key('room-list'),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is RoomListSection) {
                return _RoomSectionHeader(section: item, store: store);
              }
              return _roomRow(context, item as String, rowExtent);
            },
          );
        },
      ),
    );
  }
}

class _RoomSectionHeader extends StatelessWidget {
  const _RoomSectionHeader({required this.section, required this.store});

  final RoomListSection section;
  final RoomListStateStore store;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        store.sectionLayoutRevision.value;
        final collapsed = store.collapsedSectionIds.value.contains(section.id);
        final unreadCount = store.sectionUnreadCount(section.id);
        final colors = Theme.of(context).colorScheme;
        return SizedBox(
          key: Key('room-section-${section.id}'),
          height: 44,
          child: Material(
            color: context.kiteColors.canvas,
            child: InkWell(
              key: Key('room-section-toggle-${section.id}'),
              onTap: () => store.toggleSectionCollapsed(section.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
                child: Row(
                  children: <Widget>[
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: KiteMotion.resolve(context, KiteMotion.fast),
                      curve: KiteMotion.standardCurve,
                      child: const Icon(Icons.expand_more_rounded, size: 20),
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                    Expanded(
                      child: Text(
                        section.name,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        key: Key('room-section-unread-${section.id}'),
                        constraints: const BoxConstraints(minWidth: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(KiteRadii.pill),
                        ),
                        child: Text(
                          '$unreadCount',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomListRow extends StatefulWidget {
  const _RoomListRow({
    super.key,
    required this.room,
    required this.selected,
    required this.unreadThreadCount,
    required this.onTap,
    this.onLongPress,
  });

  final RoomListEntry room;
  final bool selected;
  final int unreadThreadCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_RoomListRow> createState() => _RoomListRowState();
}

class _RoomListRowState extends State<_RoomListRow> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'Room ${widget.room.id}')
      ..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final selected = widget.selected;
    final unreadThreadCount = widget.unreadThreadCount;
    final theme = Theme.of(context);
    final colors =
        theme.extension<KiteSemanticColors>() ??
        KiteSemanticColors.forBrightness(theme.brightness, theme.colorScheme);
    final previewStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: room.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
    );
    final sender = room.latestSender;
    final preview = sender == null || sender.isEmpty
        ? room.latestEventBody
        : '$sender: ${room.latestEventBody}';
    final semantics = <String>[
      room.name,
      preview,
      if (room.unreadCount > 0) '${room.unreadCount} unread',
      if (room.hasMention) 'Mention',
      if (room.hasMutedActivity) 'Muted room has new activity',
      if (room.hasActiveCall) 'Active call',
      if (room.isMuted) 'Muted',
      if (room.isFavourite) 'Favourite',
      if (unreadThreadCount > 0)
        AppLocalizations.of(context)
            .unreadThreadRepliesLabel(unreadThreadCount),
    ].join(', ');

    return DecoratedBox(
      key: Key('room-focus-${room.id}'),
      decoration: BoxDecoration(
        border: Border.all(
          color: _focused ? theme.colorScheme.primary : Colors.transparent,
          width: KiteStroke.emphasis,
        ),
        borderRadius: BorderRadius.circular(KiteRadii.sm),
      ),
      child: Material(
        color: selected
            ? colors.selected.withValues(alpha: 0.62)
            : Colors.transparent,
        child: ListTile(
          key: Key('room-${room.id}'),
          focusNode: _focusNode,
          focusColor: Colors.transparent,
          selected: selected,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KiteSpacing.md,
          ),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: selected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Text(
              room.name.characters.first,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Semantics(
            label: semantics,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    room.name,
                    key: Key('room-title-${room.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: selected || room.unreadCount > 0
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (room.hasActiveCall)
                  Padding(
                    padding: const EdgeInsets.only(left: KiteSpacing.xs),
                    child: Icon(
                      Icons.call_rounded,
                      key: Key('room-active-call-${room.id}'),
                      size: 16,
                      color: colors.unread,
                    ),
                  ),
                if (room.isMuted)
                  Padding(
                    padding: const EdgeInsets.only(left: KiteSpacing.xs),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      key: Key('room-muted-${room.id}'),
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (room.isFavourite)
                  Padding(
                    padding: const EdgeInsets.only(left: KiteSpacing.xs),
                    child: Icon(
                      Icons.star_rounded,
                      key: Key('room-favourite-${room.id}'),
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          subtitle: Text(
            preview,
            key: Key('room-preview-${room.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: previewStyle,
          ),
          trailing: SizedBox(
            width: 52,
            child: Align(
              alignment: Alignment.centerRight,
              child: _RoomIndicators(
                room: room,
                unreadThreadCount: unreadThreadCount,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomIndicators extends StatelessWidget {
  const _RoomIndicators({required this.room, required this.unreadThreadCount});

  final RoomListEntry room;
  final int unreadThreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<KiteSemanticColors>() ??
        KiteSemanticColors.forBrightness(theme.brightness, theme.colorScheme);
    final textTheme = theme.textTheme;
    Widget primary;
    if (room.hasMention) {
      primary = Container(
        key: Key('room-mention-${room.id}'),
        constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colors.mention,
          borderRadius: BorderRadius.circular(KiteRadii.pill),
        ),
        child: Text(
          '@${room.unreadCount > 0 ? room.unreadCount : ''}',
          style: textTheme.labelSmall?.copyWith(
            color:
                ThemeData.estimateBrightnessForColor(colors.mention) ==
                    Brightness.dark
                ? Colors.white
                : Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else if (room.unreadCount > 0) {
      primary = Container(
        key: Key('room-unread-${room.id}'),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colors.unread,
          borderRadius: BorderRadius.circular(KiteRadii.pill),
        ),
        child: Text(
          '${room.unreadCount}',
          style: textTheme.labelSmall?.copyWith(
            color:
                ThemeData.estimateBrightnessForColor(colors.unread) ==
                    Brightness.dark
                ? Colors.white
                : Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else if (room.hasMutedActivity) {
      primary = Container(
        key: Key('room-muted-activity-${room.id}'),
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant
              .withValues(alpha: 0.72),
          shape: BoxShape.circle,
        ),
      );
    } else {
      primary = const SizedBox(width: 24, height: 24);
    }

    if (unreadThreadCount <= 0) return primary;
    return SizedBox(
      width: 52,
      height: 24,
      child: Stack(
        alignment: Alignment.centerRight,
        children: <Widget>[
          primary,
          Positioned(
            left: 3,
            child: Semantics(
              label: AppLocalizations.of(context)
                  .unreadThreadRepliesLabel(unreadThreadCount),
              child: Container(
                key: Key('room-thread-unread-${room.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.unread,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TextDirection _eventTextDirection(String text, TextDirection fallback) {
  if (intl.Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (intl.Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return fallback;
}

typedef _ComposerAction = void Function(String roomId, TimelineMessage message);
typedef _ReactionAction = void Function(String emoji);

enum _MessageAction {
  reply,
  edit,
  copy,
  share,
  forward,
  report,
  redact,
  reactionPicker,
}

const _reportReasons = <String>[
  'Spam or scam',
  'Harassment or abuse',
  'Inappropriate content',
  'Other',
];

const _composerEmoji = <String>[
  '😀',
  '😂',
  '🥰',
  '😍',
  '😎',
  '🤔',
  '😮',
  '😢',
  '😭',
  '😡',
  '👍',
  '👎',
  '👏',
  '🙏',
  '💪',
  '👀',
  '❤️',
  '💯',
  '🔥',
  '🎉',
  '✅',
  '🚀',
  '✨',
  '💡',
];

enum _ComposerMode { reply, edit }

enum _ComposerFormatAction {
  bold,
  italic,
  strikethrough,
  inlineCode,
  quote,
  codeBlock,
}

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
        const _TypingIndicator(),
        const Divider(height: 1),
        _Composer(key: _composerKey),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const Key('typing-indicator-slot'),
      height: 28,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.lg),
          child: SignalBuilder(
            builder: (context) {
              final roomId = selectedRoomId.value;
              final users = timelineController.typingUsersFor(roomId).value;
              final text = switch (users.length) {
                0 => '',
                1 => '${users.first} is typing…',
                2 => '${users.first} and ${users.last} are typing…',
                _ =>
                  '${users.first} and ${users.length - 1} others are typing…',
              };
              return KeyedSubtree(
                key: const Key('typing-indicator'),
                child: users.isEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: const Key('chat-header'),
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                        AppLocalizations.of(context).encryptedConversation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('room-content-gallery-action'),
                  tooltip: 'Shared content',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomContentGallery(
                          roomId: roomId,
                          messages: timelineController.messagesFor(roomId),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                ),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('room-details-button'),
                  tooltip: 'Room details',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomDetailsScreen(
                          roomId: room.id,
                          roomName: room.name,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline_rounded),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.onReply, required this.onEdit});

  final _ComposerAction onReply;
  final _ComposerAction onEdit;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _unreadMarkerKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _jumpToUnread(String roomId) async {
    final eventId = timelineController.unreadMarkerFor(roomId).peek();
    if (eventId == null || !_scrollController.hasClients) return;

    final retainedMarkerContext = _unreadMarkerKey.currentContext;
    final retainedMarker = retainedMarkerContext?.findRenderObject();
    if (retainedMarker != null && retainedMarker.attached) {
      final position = _scrollController.position;
      final viewport = RenderAbstractViewport.maybeOf(retainedMarker);
      if (viewport != null) {
        final target = viewport
            .getOffsetToReveal(retainedMarker, 0.22)
            .offset
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        final distance = (target - position.pixels).abs();
        final duration = distance > position.viewportDimension
            ? Duration.zero
            : KiteMotion.resolve(context, KiteMotion.standard);
        await position.ensureVisible(
          retainedMarker,
          alignment: 0.22,
          duration: duration,
          curve: KiteMotion.standardCurve,
        );
        return;
      }
    }

    final messages = timelineController.messagesFor(roomId).peek();
    final targetIndex = messages.indexWhere((message) => message.id == eventId);
    if (targetIndex < 0) return;
    final reverseIndex = messages.length - 1 - targetIndex;
    final denominator = messages.length <= 1 ? 1 : messages.length - 1;
    final targetOffset =
        _scrollController.position.maxScrollExtent * reverseIndex / denominator;
    await _scrollController.animateTo(
      targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: KiteMotion.resolve(context, KiteMotion.deliberate),
      curve: KiteMotion.standardCurve,
    );
    if (!mounted) return;
    final markerContext = _unreadMarkerKey.currentContext;
    if (markerContext != null && markerContext.mounted) {
      await Scrollable.ensureVisible(
        markerContext,
        alignment: 0.22,
        duration: KiteMotion.resolve(context, KiteMotion.standard),
        curve: KiteMotion.standardCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final roomId = selectedRoomId.value;
        final messages = timelineController.messagesFor(roomId).value;
        final unreadMarkerEventId = timelineController
            .unreadMarkerFor(roomId)
            .value;
        return Stack(
          key: const Key('timeline-stack'),
          children: <Widget>[
            ListView.builder(
              key: const Key('message-list'),
              controller: _scrollController,
              reverse: true,
              scrollCacheExtent: unreadMarkerEventId == null
                  ? null
                  : const ScrollCacheExtent.viewport(1.8),
              padding: const EdgeInsets.symmetric(vertical: KiteSpacing.sm),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[messages.length - 1 - index];
                final row = _MessageRow(
                  key: ValueKey<String>(message.id),
                  roomId: roomId,
                  message: message,
                  semanticsOrder: (messages.length - 1 - index).toDouble(),
                  onReply: widget.onReply,
                  onEdit: widget.onEdit,
                );
                if (message.id != unreadMarkerEventId) return row;
                return _UnreadMarkerOverlay(
                  markerKey: _unreadMarkerKey,
                  child: row,
                );
              },
            ),
            Positioned(
              right: KiteSpacing.md,
              bottom: KiteSpacing.md,
              child: SignalBuilder(
                builder: (context) {
                  final eventId = timelineController
                      .unreadMarkerFor(roomId)
                      .value;
                  return KeyedSubtree(
                    key: const Key('jump-to-unread-slot'),
                    child: eventId == null
                        ? const SizedBox.shrink()
                        : _UnreadJumpButton(onTap: () => _jumpToUnread(roomId)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnreadJumpButton extends StatelessWidget {
  const _UnreadJumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Jump to unread messages',
        child: GestureDetector(
          key: const Key('jump-to-unread'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 18,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                    Text(
                      'Unread',
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadMarkerOverlay extends StatelessWidget {
  const _UnreadMarkerOverlay({required this.markerKey, required this.child});

  final GlobalKey markerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          key: markerKey,
          left: KiteSpacing.md,
          right: KiteSpacing.md,
          top: 0,
          child: IgnorePointer(
            child: SizedBox(
              key: const Key('timeline-unread-marker'),
              height: 1,
              child: ColoredBox(color: colors.primary.withValues(alpha: 0.72)),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.roomId,
    required this.message,
    required this.semanticsOrder,
    required this.onReply,
    required this.onEdit,
  });

  final String roomId;
  final TimelineMessage message;
  final double semanticsOrder;
  final _ComposerAction onReply;
  final _ComposerAction onEdit;

  void _openMedia(BuildContext context) {
    final model = TimelineMediaViewerModel.fromMessages(
      roomId: roomId,
      messages: timelineController.messagesFor(roomId).peek(),
      initialMessageId: message.id,
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

  Future<void> _showEditHistory(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.kiteColors.canvas,
      constraints: const BoxConstraints(maxWidth: 440),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
      ),
      builder: (_) => _EditHistorySheet(message: message),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.kiteColors.canvas,
      constraints: const BoxConstraints(maxWidth: 440),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
      ),
      builder: (sheetContext) => _MessageActionSheet(
        message: message,
        onReact: (emoji) {
          timelineController.toggleReaction(message, emoji);
          Navigator.of(sheetContext).pop();
        },
      ),
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
            SnackBar(
              content: Text(AppLocalizations.of(context).messageCopied),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      case _MessageAction.share:
        await timelineController.shareMessage(roomId, message);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Share sheet opened'),
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
          builder: (_) =>
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
          builder: (_) => _ReportMessageSheet(message: message),
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
          builder: (_) => const _ReactionPickerSheet(),
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

  Future<void> _performAccessibleAction(
    BuildContext context,
    _MessageAction action,
  ) async {
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
            SnackBar(
              content: Text(AppLocalizations.of(context).messageCopied),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
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
        if (confirmed == true) timelineController.redactText(message);
      case _MessageAction.share:
      case _MessageAction.forward:
      case _MessageAction.report:
      case _MessageAction.reactionPicker:
        return;
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

    final localizations = AppLocalizations.of(context);
    final bubble = _KeyboardActionFrame(
      focusKey: Key('message-focus-${message.id}'),
      frameKey: Key('message-focus-frame-${message.id}'),
      borderRadius: bubbleRadius,
      enabled: !message.redacted,
      onActivate: () => unawaited(_showActions(context)),
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        onSecondaryTap: () => _showActions(context),
        child: Semantics(
          customSemanticsActions: message.redacted
              ? const <CustomSemanticsAction, VoidCallback>{}
              : <CustomSemanticsAction, VoidCallback>{
                  CustomSemanticsAction(label: localizations.replyAction): () =>
                      unawaited(
                        _performAccessibleAction(context, _MessageAction.reply),
                      ),
                  CustomSemanticsAction(
                    label: localizations.copyTextAction,
                  ): () => unawaited(
                    _performAccessibleAction(context, _MessageAction.copy),
                  ),
                  if (message.mine)
                    CustomSemanticsAction(
                      label: localizations.editMessageAction,
                    ): () => unawaited(
                      _performAccessibleAction(context, _MessageAction.edit),
                    ),
                  if (message.mine)
                    CustomSemanticsAction(
                      label: localizations.deleteMessageAction,
                    ): () => unawaited(
                      _performAccessibleAction(context, _MessageAction.redact),
                    ),
                },
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
                              AppLocalizations.of(context).messageDeleted,
                              style: KiteTypography.body.copyWith(
                                color: colors.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        );
                      }
                      final attachment = message.attachment;
                      final linkPreview = timelineLinkPreviewForText(
                        message.body,
                      );
                      return Column(
                        key: Key('message-content-${message.id}'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (attachment != null)
                            TimelineAttachmentCard(
                              messageId: message.id,
                              attachment: attachment,
                              heroTag:
                                  attachment.kind == TimelineAttachmentKind.file
                                  ? null
                                  : timelineMediaHeroTag(message),
                              onTap:
                                  attachment.kind == TimelineAttachmentKind.file
                                  ? null
                                  : () => _openMedia(context),
                            ),
                          if (attachment != null && message.body.isNotEmpty)
                            const SizedBox(height: KiteSpacing.xs),
                          if (message.body.isNotEmpty)
                            TimelineMessageBody(
                              body: message.body,
                              textKey: Key('message-body-${message.id}'),
                            ),
                          if (linkPreview != null) ...<Widget>[
                            const SizedBox(height: KiteSpacing.xs),
                            TimelineLinkPreviewCard(
                              key: Key('message-link-preview-${message.id}'),
                              preview: linkPreview,
                              onOpen: () async {
                                await timelineController.openLink(
                                  linkPreview.uri,
                                );
                              },
                            ),
                          ],
                        ],
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
                            ? Semantics(
                                button: true,
                                label: 'View edit history',
                                child: GestureDetector(
                                  key: Key('edited-${message.id}'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showEditHistory(context),
                                  child: Text(
                                    ' · ${AppLocalizations.of(context).editedLabel}',
                                    style: KiteTypography.metadata.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      _MessageReactionSummary(message: message),
                      if (mine) ...<Widget>[
                        const SizedBox(width: KiteSpacing.xxs),
                        _MessageDeliveryState(roomId: roomId, message: message),
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

    final threadedBubble = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        bubble,
        if (threadController.hasThread(message.id)) ...<Widget>[
          const SizedBox(height: KiteSpacing.xs),
          _ThreadSummaryButton(roomId: roomId, parent: message),
        ],
      ],
    );

    return Semantics(
      sortKey: OrdinalSortKey(semanticsOrder),
      child: Padding(
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
                    ? threadedBubble
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
                          threadedBubble,
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

class _KeyboardActionFrame extends StatefulWidget {
  const _KeyboardActionFrame({
    required this.focusKey,
    required this.frameKey,
    required this.borderRadius,
    required this.enabled,
    required this.onActivate,
    required this.child,
  });

  final Key focusKey;
  final Key frameKey;
  final BorderRadius borderRadius;
  final bool enabled;
  final VoidCallback onActivate;
  final Widget child;

  @override
  State<_KeyboardActionFrame> createState() => _KeyboardActionFrameState();
}

class _KeyboardActionFrameState extends State<_KeyboardActionFrame> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Message actions');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      key: widget.focusKey,
      focusNode: _focusNode,
      enabled: widget.enabled,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onActivate();
            return null;
          },
        ),
      },
      onFocusChange: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      child: DecoratedBox(
        key: widget.frameKey,
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: KiteStroke.emphasis,
          ),
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ThreadSummaryButton extends StatelessWidget {
  const _ThreadSummaryButton({required this.roomId, required this.parent});

  final String roomId;
  final TimelineMessage parent;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      ThreadRoute(
        roomId: roomId,
        parent: parent,
        reduceMotion: KiteMotion.prefersReducedMotion(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SignalBuilder(
      builder: (context) {
        final replies = threadController
            .repliesFor(roomId: roomId, parent: parent)
            .value;
        final count = replies.length;
        if (count == 0) return const SizedBox.shrink();
        final unread = threadController
            .unreadCountFor(roomId: roomId, parent: parent)
            .value;
        final latest = replies.last;
        return Semantics(
          button: true,
          label:
              'Open thread with $count replies${unread > 0 ? ', $unread unread' : ''}',
          child: InkWell(
            key: Key('thread-summary-${parent.id}'),
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(KiteRadii.md),
            child: Container(
              constraints: const BoxConstraints(minWidth: 168, maxWidth: 360),
              padding: const EdgeInsets.symmetric(
                horizontal: KiteSpacing.sm,
                vertical: KiteSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(KiteRadii.md),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                  width: KiteStroke.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox.square(
                    dimension: 20,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(
                            Icons.forum_outlined,
                            size: 17,
                            color: colors.primary,
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            key: Key('thread-unread-${parent.id}'),
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.surfaceContainerHighest,
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.xs),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '$count ${count == 1 ? 'reply' : 'replies'}',
                          style: KiteTypography.metadata.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${latest.sender}: ${latest.body}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KiteTypography.metadata.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
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
            textDirection: _eventTextDirection(
              message.replyToBody ?? '',
              Directionality.of(context),
            ),
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

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({required this.message, required this.onReact});

  final TimelineMessage message;
  final _ReactionAction onReact;

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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: SingleChildScrollView(
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
                _QuickReactionRow(onReact: onReact),
                const SizedBox(height: KiteSpacing.xs),
                _MessageActionButton(
                  key: const Key('message-action-more-reactions'),
                  icon: Icons.add_reaction_outlined,
                  label: 'More reactions',
                  onTap: () =>
                      Navigator.of(context).pop(_MessageAction.reactionPicker),
                ),
                _MessageActionButton(
                  key: const Key('message-action-reply'),
                  icon: Icons.reply_rounded,
                  label: AppLocalizations.of(context).replyAction,
                  onTap: () => Navigator.of(context).pop(_MessageAction.reply),
                ),
                _MessageActionButton(
                  key: const Key('message-action-copy'),
                  icon: Icons.content_copy_rounded,
                  label: AppLocalizations.of(context).copyTextAction,
                  onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                ),
                _MessageActionButton(
                  key: const Key('message-action-share'),
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () => Navigator.of(context).pop(_MessageAction.share),
                ),
                _MessageActionButton(
                  key: const Key('message-action-forward'),
                  icon: Icons.forward_to_inbox_rounded,
                  label: 'Forward',
                  onTap: () =>
                      Navigator.of(context).pop(_MessageAction.forward),
                ),
                if (!message.mine)
                  _MessageActionButton(
                    key: const Key('message-action-report'),
                    icon: Icons.flag_outlined,
                    label: 'Report',
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.report),
                  ),
                if (message.mine)
                  _MessageActionButton(
                    key: const Key('message-action-edit'),
                    icon: Icons.edit_outlined,
                    label: AppLocalizations.of(context).editMessageAction,
                    onTap: () => Navigator.of(context).pop(_MessageAction.edit),
                  ),
                if (message.mine)
                  _MessageActionButton(
                    key: const Key('message-action-delete'),
                    icon: Icons.delete_outline_rounded,
                    label: AppLocalizations.of(context).deleteMessageAction,
                    destructive: true,
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.redact),
                  ),
              ],
            ],
          ),
        ),
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
                    void toggle() {
                      setState(() {
                        if (!_selectedRoomIds.add(room.id)) {
                          _selectedRoomIds.remove(room.id);
                        }
                      });
                    }

                    return InkWell(
                      key: Key('forward-room-${room.id}'),
                      onTap: toggle,
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
                          Checkbox(value: selected, onChanged: (_) => toggle()),
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

class _QuickReactionRow extends StatelessWidget {
  const _QuickReactionRow({required this.onReact});

  final _ReactionAction onReact;

  static const reactions = <String>['👍', '❤️', '😂', '🎉'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('quick-reaction-row'),
      height: 46,
      child: Row(
        children: <Widget>[
          for (var index = 0; index < reactions.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: KiteSpacing.xs),
            Expanded(
              child: Semantics(
                button: true,
                label: 'React with ${reactions[index]}',
                child: InkWell(
                  key: Key('quick-reaction-$index'),
                  onTap: () => onReact(reactions[index]),
                  borderRadius: BorderRadius.circular(KiteRadii.pill),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(KiteRadii.pill),
                    ),
                    child: Center(
                      child: Text(
                        reactions[index],
                        style: const TextStyle(fontSize: 21),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReactionPickerSheet extends StatelessWidget {
  const _ReactionPickerSheet();

  static const emoji = <String>[
    '👍',
    '❤️',
    '😂',
    '🎉',
    '🔥',
    '👏',
    '👀',
    '🤔',
    '😮',
    '😢',
    '🙏',
    '✅',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('reaction-picker-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.sm,
        KiteSpacing.lg,
        KiteSpacing.xl,
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
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: KiteSpacing.md),
          Text(
            'Choose a reaction',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: KiteSpacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: KiteSpacing.xs,
              crossAxisSpacing: KiteSpacing.xs,
            ),
            itemCount: emoji.length,
            itemBuilder: (context, index) {
              return InkWell(
                key: Key('reaction-picker-$index'),
                onTap: () => Navigator.of(context).pop(emoji[index]),
                borderRadius: BorderRadius.circular(KiteRadii.md),
                child: Center(
                  child: Text(
                    emoji[index],
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MessageReactionSummary extends StatelessWidget {
  const _MessageReactionSummary({required this.message});

  final TimelineMessage message;

  Future<void> _showDetails(
    BuildContext context,
    TimelineReactionSummary reaction,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        key: const Key('reaction-details'),
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.lg,
          KiteSpacing.sm,
          KiteSpacing.lg,
          KiteSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${reaction.emoji} ${reaction.count}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: KiteSpacing.sm),
            for (final reactor in reaction.reactors)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.person_rounded, size: 18),
                ),
                title: Text(reactor),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final reactions = message.reactions.values.toList(growable: false);
        if (reactions.isEmpty) {
          return const SizedBox.shrink();
        }
        final primary = reactions.first;
        final extraCount = reactions.length - 1;
        return Padding(
          padding: const EdgeInsets.only(left: KiteSpacing.xxs),
          child: InkWell(
            key: Key('message-reactions-${message.id}'),
            onTap: () => _showDetails(context, primary),
            borderRadius: BorderRadius.circular(KiteRadii.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '${primary.emoji} ${primary.count}${extraCount > 0 ? ' +$extraCount' : ''}',
                style: KiteTypography.metadata.copyWith(
                  color: primary.reactedByMe
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
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
                AppLocalizations.of(context).deleteMessageTitle,
                style: KiteTypography.title.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: KiteSpacing.sm),
              Text(
                AppLocalizations.of(context).deleteMessageBody,
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
                    child: Text(AppLocalizations.of(context).cancelAction),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  FilledButton(
                    key: const Key('delete-message-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    child: Text(AppLocalizations.of(context).deleteAction),
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
      label: AppLocalizations.of(context).avatarLabel(sender),
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

class _MessageDeliveryState extends StatelessWidget {
  const _MessageDeliveryState({required this.roomId, required this.message});

  final String roomId;
  final TimelineMessage message;

  Future<void> _showReadReceipts(BuildContext context, List<String> readers) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.kiteColors.canvas,
      constraints: const BoxConstraints(maxWidth: 440),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
      ),
      builder: (_) => _ReadReceiptDetailsSheet(readers: readers),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final state = message.sendState.value;
        final readers = message.readByState.value;
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
                semanticLabel: AppLocalizations.of(context).sendingLabel,
              ),
            ),
            TimelineSendState.sent when readers.isNotEmpty => Semantics(
              button: true,
              label: 'Read by ${readers.join(', ')}',
              child: Tooltip(
                message: 'Read by ${readers.join(', ')}',
                child: GestureDetector(
                  key: Key('read-receipts-${message.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showReadReceipts(context, readers),
                  child: _ReadReceiptAvatars(readers: readers),
                ),
              ),
            ),
            TimelineSendState.sent => Center(
              child: Icon(
                Icons.done_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
                semanticLabel: AppLocalizations.of(context).sentLabel,
              ),
            ),
            TimelineSendState.failed => Tooltip(
              message: AppLocalizations.of(context).retrySendingLabel,
              child: InkWell(
                key: Key('retry-${message.id}'),
                borderRadius: BorderRadius.circular(KiteRadii.pill),
                onTap: () => timelineController.retry(roomId, message),
                child: Center(
                  child: Icon(
                    Icons.error_rounded,
                    size: 16,
                    color: colors.error,
                    semanticLabel: AppLocalizations.of(context)
                        .messageFailedRetryLabel,
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

class _ReadReceiptAvatars extends StatelessWidget {
  const _ReadReceiptAvatars({required this.readers});

  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = readers.take(3).toList(growable: false);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (var index = 0; index < visible.length; index++)
          Positioned(
            left: 4.0 + (index * 10),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surfaceContainerHighest),
              ),
              alignment: Alignment.center,
              child: Text(
                visible[index].characters.first.toUpperCase(),
                style: KiteTypography.metadata.copyWith(
                  color: colors.onSecondaryContainer,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (readers.length > 3)
          Positioned(
            right: 0,
            child: Text(
              '+${readers.length - 3}',
              style: KiteTypography.metadata.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _EditHistorySheet extends StatelessWidget {
  const _EditHistorySheet({required this.message});

  final TimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('edit-history-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.md,
        KiteSpacing.lg,
        KiteSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Edit history',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: KiteSpacing.md),
          _EditHistoryEntry(
            key: const Key('edit-history-current'),
            label: 'Current',
            body: message.body,
            emphasized: true,
          ),
          for (var index = message.editHistory.length - 1; index >= 0; index--)
            _EditHistoryEntry(
              key: Key('edit-history-$index'),
              label: index == 0 ? 'Original' : 'Earlier edit',
              body: message.editHistory[index],
            ),
          if (message.editHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: KiteSpacing.sm),
              child: Text(
                'Earlier versions are unavailable.',
                style: KiteTypography.metadata.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditHistoryEntry extends StatelessWidget {
  const _EditHistoryEntry({
    super.key,
    required this.label,
    required this.body,
    this.emphasized = false,
  });

  final String label;
  final String body;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: KiteSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: KiteTypography.metadata.copyWith(
              color: emphasized ? colors.primary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KiteSpacing.xxs),
          Text(
            body,
            style: KiteTypography.body.copyWith(color: colors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _ReadReceiptDetailsSheet extends StatelessWidget {
  const _ReadReceiptDetailsSheet({required this.readers});

  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('read-receipt-details'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.md,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Read by',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KiteSpacing.sm),
          for (final reader in readers)
            SizedBox(
              height: 48,
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                    child: Text(
                      reader.characters.first.toUpperCase(),
                      style: KiteTypography.metadata.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  Expanded(
                    child: Text(
                      reader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KiteTypography.body,
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
  TimelineAttachment? _pendingAttachment;
  String? _pendingAttachmentRoomId;
  bool _formattingVisible = false;
  final OverlayPortalController _emojiOverlayController =
      OverlayPortalController();
  final LayerLink _emojiLayerLink = LayerLink();

  static const _autocompleteCandidates =
      <({String token, String label, IconData icon})>[
        (token: '@Alice', label: 'Alice', icon: Icons.person_outline_rounded),
        (token: '@Maya', label: 'Maya', icon: Icons.person_outline_rounded),
        (token: '@Sam', label: 'Sam', icon: Icons.person_outline_rounded),
        (token: '#Kite', label: 'Kite', icon: Icons.tag_rounded),
        (token: '#Design-Lab', label: 'Design Lab', icon: Icons.tag_rounded),
      ];

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

  Future<void> _pickAttachment(String roomId) async {
    final attachment = await showComposerAttachmentPicker(context);
    if (!mounted || attachment == null) return;
    setState(() {
      _pendingAttachment = attachment;
      _pendingAttachmentRoomId = roomId;
    });
    _focusNode.requestFocus();
  }

  void _removeAttachment() {
    if (_pendingAttachment == null) return;
    setState(() {
      _pendingAttachment = null;
      _pendingAttachmentRoomId = null;
    });
  }

  void _toggleFormatting() {
    if (_emojiOverlayController.isShowing) {
      _emojiOverlayController.hide();
    }
    setState(() => _formattingVisible = !_formattingVisible);
    _focusNode.requestFocus();
  }

  void _toggleEmojiPicker() {
    if (_emojiOverlayController.isShowing) {
      _emojiOverlayController.hide();
      _focusNode.requestFocus();
      return;
    }
    if (_formattingVisible) setState(() => _formattingVisible = false);
    _emojiOverlayController.show();
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    _controller.value = value
        .replaced(TextRange(start: start, end: end), emoji)
        .copyWith(
          selection: TextSelection.collapsed(offset: start + emoji.length),
          composing: TextRange.empty,
        );
    _emojiOverlayController.hide();
    _focusNode.requestFocus();
  }

  ({int start, String prefix, String query})? _autocompleteMatch(
    TextEditingValue value,
  ) {
    final selection = value.selection;
    if (selection.isValid && !selection.isCollapsed) return null;
    final cursorOffset = selection.isValid
        ? selection.extentOffset
        : value.text.length;
    final beforeCursor = value.text.substring(0, cursorOffset);
    final match = RegExp(r'([@#])([^\s@#]*)$').firstMatch(beforeCursor);
    if (match == null) return null;
    final start = match.start;
    if (start > 0 && !RegExp(r'\s').hasMatch(beforeCursor[start - 1])) {
      return null;
    }
    return (
      start: start,
      prefix: match.group(1)!,
      query: match.group(2)!.toLowerCase(),
    );
  }

  List<({String token, String label, IconData icon})> _autocompleteOptions(
    TextEditingValue value,
  ) {
    final match = _autocompleteMatch(value);
    if (match == null) return const [];
    return _autocompleteCandidates
        .where(
          (candidate) =>
              candidate.token.startsWith(match.prefix) &&
              candidate.label.toLowerCase().startsWith(match.query),
        )
        .take(4)
        .toList(growable: false);
  }

  void _insertAutocompleteToken(
    ({String token, String label, IconData icon}) candidate,
  ) {
    final value = _controller.value;
    final match = _autocompleteMatch(value);
    if (match == null) return;
    final end = value.selection.extentOffset;
    final replacement = '${candidate.token} ';
    _controller.value = value
        .replaced(TextRange(start: match.start, end: end), replacement)
        .copyWith(
          selection: TextSelection.collapsed(
            offset: match.start + replacement.length,
          ),
          composing: TextRange.empty,
        );
    _focusNode.requestFocus();
  }

  void _applyFormat(_ComposerFormatAction action) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final selected = value.text.substring(start, end);

    late final String replacement;
    late final TextSelection nextSelection;
    switch (action) {
      case _ComposerFormatAction.quote:
        replacement = selected.isEmpty
            ? '> '
            : selected.split('\n').map((line) => '> $line').join('\n');
        nextSelection = TextSelection.collapsed(
          offset: start + replacement.length,
        );
      case _ComposerFormatAction.codeBlock:
        replacement = selected.isEmpty ? '```\n\n```' : '```\n$selected\n```';
        nextSelection = selected.isEmpty
            ? TextSelection.collapsed(offset: start + 4)
            : TextSelection(
                baseOffset: start + 4,
                extentOffset: start + 4 + selected.length,
              );
      case _ComposerFormatAction.bold:
        (replacement, nextSelection) = _wrapComposerSelection(
          start: start,
          selected: selected,
          marker: '**',
        );
      case _ComposerFormatAction.italic:
        (replacement, nextSelection) = _wrapComposerSelection(
          start: start,
          selected: selected,
          marker: '*',
        );
      case _ComposerFormatAction.strikethrough:
        (replacement, nextSelection) = _wrapComposerSelection(
          start: start,
          selected: selected,
          marker: '~~',
        );
      case _ComposerFormatAction.inlineCode:
        (replacement, nextSelection) = _wrapComposerSelection(
          start: start,
          selected: selected,
          marker: '`',
        );
    }

    _controller.value = value
        .replaced(selection, replacement)
        .copyWith(selection: nextSelection, composing: TextRange.empty);
    _focusNode.requestFocus();
  }

  (String, TextSelection) _wrapComposerSelection({
    required int start,
    required String selected,
    required String marker,
  }) {
    final replacement = '$marker$selected$marker';
    if (selected.isEmpty) {
      return (
        replacement,
        TextSelection.collapsed(offset: start + marker.length),
      );
    }
    return (
      replacement,
      TextSelection(
        baseOffset: start + marker.length,
        extentOffset: start + marker.length + selected.length,
      ),
    );
  }

  void _send() {
    final body = _controller.text.trim();
    final roomId = selectedRoomId.value;
    final attachment = _pendingAttachmentRoomId == roomId
        ? _pendingAttachment
        : null;
    final contextMessage = _contextRoomId == roomId ? _contextMessage : null;
    if (_mode == _ComposerMode.edit && contextMessage != null) {
      if (body.isEmpty) return;
      timelineController.editText(contextMessage, body);
      _clearContext(restoreEditDraft: true);
    } else {
      if (body.isEmpty && attachment == null) return;
      if (attachment != null) {
        timelineController.sendAttachment(
          roomId,
          attachment,
          caption: body,
          replyTo: _mode == _ComposerMode.reply ? contextMessage : null,
        );
        _pendingAttachment = null;
        _pendingAttachmentRoomId = null;
      } else {
        timelineController.sendText(
          roomId,
          body,
          replyTo: _mode == _ComposerMode.reply ? contextMessage : null,
        );
      }
      _controller.clear();
      if (_mode != null) _clearContext(restoreEditDraft: false);
      if (mounted) setState(() {});
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
        final activeAttachment = _pendingAttachmentRoomId == roomId
            ? _pendingAttachment
            : null;
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
                if (activeAttachment != null)
                  ComposerAttachmentPreview(
                    attachment: activeAttachment,
                    onRemove: _removeAttachment,
                  ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, child) {
                    final options = _autocompleteOptions(value);
                    return AnimatedSize(
                      key: const Key('composer-autocomplete-slot'),
                      alignment: Alignment.bottomCenter,
                      duration: KiteMotion.resolve(
                        context,
                        KiteMotion.standard,
                      ),
                      curve: KiteMotion.standardCurve,
                      child: options.isEmpty
                          ? const SizedBox.shrink()
                          : _ComposerAutocompleteBar(
                              options: options,
                              onSelected: _insertAutocompleteToken,
                            ),
                    );
                  },
                ),
                AnimatedSize(
                  key: const Key('composer-formatting-slot'),
                  alignment: Alignment.bottomCenter,
                  duration: KiteMotion.resolve(context, KiteMotion.standard),
                  curve: KiteMotion.standardCurve,
                  child: _formattingVisible
                      ? _ComposerFormattingToolbar(onFormat: _applyFormat)
                      : const SizedBox.shrink(),
                ),
                CompositedTransformTarget(
                  link: _emojiLayerLink,
                  child: OverlayPortal(
                    controller: _emojiOverlayController,
                    overlayChildBuilder: (overlayContext) {
                      final width =
                          (MediaQuery.sizeOf(overlayContext).width - 24).clamp(
                            240.0,
                            440.0,
                          );
                      return CompositedTransformFollower(
                        link: _emojiLayerLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topCenter,
                        followerAnchor: Alignment.bottomCenter,
                        offset: const Offset(0, -KiteSpacing.xs),
                        child: SizedBox(
                          width: width,
                          child: _ComposerEmojiPicker(onSelected: _insertEmoji),
                        ),
                      );
                    },
                    child: SizedBox(
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
                              tooltip: AppLocalizations.of(context)
                                  .addAttachmentTooltip,
                              onPressed: activeMode == _ComposerMode.edit
                                  ? null
                                  : () => _pickAttachment(roomId),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                            ),
                            IconButton(
                              key: const Key('composer-format-toggle'),
                              tooltip: _formattingVisible
                                  ? 'Hide formatting'
                                  : 'Show formatting',
                              onPressed: _toggleFormatting,
                              icon: Icon(
                                _formattingVisible
                                    ? Icons.text_format_rounded
                                    : Icons.text_format_outlined,
                              ),
                            ),
                            IconButton(
                              key: const Key('composer-emoji'),
                              tooltip: 'Emoji',
                              onPressed: _toggleEmojiPicker,
                              icon: const Icon(Icons.emoji_emotions_outlined),
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
                                      ? AppLocalizations.of(context)
                                            .editMessageHint
                                      : activeAttachment != null
                                      ? 'Add a caption…'
                                      : AppLocalizations.of(context)
                                            .messageHint,
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
                                      color: colors.primary.withValues(
                                        alpha: 0.42,
                                      ),
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
                                final editing =
                                    activeMode == _ComposerMode.edit;
                                final enabled = editing
                                    ? value.text.trim().isNotEmpty
                                    : value.text.trim().isNotEmpty ||
                                          activeAttachment != null;
                                return IconButton.filled(
                                  key: const Key('composer-send'),
                                  tooltip: editing
                                      ? AppLocalizations.of(context)
                                            .saveEditTooltip
                                      : AppLocalizations.of(context)
                                            .sendMessageTooltip,
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

class _ComposerAutocompleteBar extends StatelessWidget {
  const _ComposerAutocompleteBar({
    required this.options,
    required this.onSelected,
  });

  final List<({String token, String label, IconData icon})> options;
  final ValueChanged<({String token, String label, IconData icon})> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('composer-autocomplete'),
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xs),
        itemBuilder: (context, index) {
          final option = options[index];
          return ActionChip(
            key: Key('composer-autocomplete-${option.token.substring(1)}'),
            avatar: Icon(option.icon, size: 17, color: colors.onSurfaceVariant),
            label: Text(option.token),
            onPressed: () => onSelected(option),
          );
        },
      ),
    );
  }
}

class _ComposerEmojiPicker extends StatelessWidget {
  const _ComposerEmojiPicker({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Material(
        key: const Key('composer-emoji-sheet'),
        elevation: KiteElevation.floating,
        color: context.kiteColors.canvas,
        borderRadius: BorderRadius.circular(KiteRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 64,
          child: ListView.separated(
            key: const Key('composer-emoji-list'),
            padding: const EdgeInsets.symmetric(
              horizontal: KiteSpacing.xs,
              vertical: KiteSpacing.xs,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: _composerEmoji.length,
            separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xxs),
            itemBuilder: (context, index) {
              final emoji = _composerEmoji[index];
              return Semantics(
                button: true,
                label: 'Insert $emoji',
                child: InkWell(
                  key: Key('composer-emoji-$index'),
                  onTap: () => onSelected(emoji),
                  borderRadius: BorderRadius.circular(KiteRadii.md),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Text(
                        emoji,
                        style: TextStyle(fontSize: 26, color: colors.onSurface),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ComposerFormattingToolbar extends StatelessWidget {
  const _ComposerFormattingToolbar({required this.onFormat});

  final ValueChanged<_ComposerFormatAction> onFormat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const actions =
        <({_ComposerFormatAction action, IconData icon, String tooltip})>[
          (
            action: _ComposerFormatAction.bold,
            icon: Icons.format_bold_rounded,
            tooltip: 'Bold',
          ),
          (
            action: _ComposerFormatAction.italic,
            icon: Icons.format_italic_rounded,
            tooltip: 'Italic',
          ),
          (
            action: _ComposerFormatAction.strikethrough,
            icon: Icons.strikethrough_s_rounded,
            tooltip: 'Strikethrough',
          ),
          (
            action: _ComposerFormatAction.inlineCode,
            icon: Icons.code_rounded,
            tooltip: 'Inline code',
          ),
          (
            action: _ComposerFormatAction.quote,
            icon: Icons.format_quote_rounded,
            tooltip: 'Quote',
          ),
          (
            action: _ComposerFormatAction.codeBlock,
            icon: Icons.data_object_rounded,
            tooltip: 'Code block',
          ),
        ];

    return SizedBox(
      key: const Key('composer-formatting-toolbar'),
      height: 52,
      child: ListView.separated(
        key: const Key('composer-formatting-actions'),
        padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xxs),
        itemBuilder: (context, index) {
          final action = actions[index];
          return SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: Key('composer-format-${action.action.name}'),
              tooltip: action.tooltip,
              onPressed: () => onFormat(action.action),
              style: IconButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                backgroundColor: colors.surfaceContainerLow,
              ),
              icon: Icon(action.icon, size: 20),
            ),
          );
        },
      ),
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
                  editing
                      ? AppLocalizations.of(context).editingMessageLabel
                      : AppLocalizations.of(context)
                            .replyingToLabel(message.sender),
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
            tooltip: editing
                ? AppLocalizations.of(context).cancelEditTooltip
                : AppLocalizations.of(context).cancelReplyTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}
