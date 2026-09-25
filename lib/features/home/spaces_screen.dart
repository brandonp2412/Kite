import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/rooms/room_creation_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_settings_screen.dart';
import 'package:kite/l10n/kite_local_formats.dart';
import 'package:signals/signals_flutter.dart';

class SpacesRoute extends PageRouteBuilder<void> {
  SpacesRoute({
    required bool reduceMotion,
    SpacesController? controller,
    RoomManagementCoordinator? roomCreation,
    RoomAvatarMediaPort? avatarMedia,
  }) : super(
         transitionDuration: reduceMotion ? Duration.zero : KiteMotion.standard,
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : KiteMotion.standard,
         pageBuilder: (context, animation, secondaryAnimation) => SpacesScreen(
           controller: controller,
           roomCreation: roomCreation,
           avatarMedia: avatarMedia,
         ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (reduceMotion) return child;
           final curved = CurvedAnimation(
             parent: animation,
             curve: KiteMotion.standardCurve,
             reverseCurve: KiteMotion.standardCurve,
           );
           return SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.08, 0),
               end: Offset.zero,
             ).animate(curved),
             child: child,
           );
         },
       );
}

class SpacesScreen extends StatelessWidget {
  const SpacesScreen({
    super.key,
    this.controller,
    this.roomCreation,
    this.avatarMedia,
  });

  final SpacesController? controller;
  final RoomManagementCoordinator? roomCreation;
  final RoomAvatarMediaPort? avatarMedia;

  SpacesController get _controller => controller ?? spacesController;

  Future<void> _openCreateSpace(BuildContext context) async {
    final coordinator = roomCreation;
    if (coordinator == null) return;
    final created = await showModalBottomSheet<KiteCreatedRoom>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CreateSpaceSheet(coordinator: coordinator),
    );
    if (created == null || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${created.displayName} created')));
  }

  Future<void> _openManageSpace(BuildContext context) async {
    final coordinator = roomCreation;
    final space = _controller.selectedSpace;
    if (coordinator == null || space == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RoomSettingsScreen(
          roomId: space.id,
          coordinator: coordinator,
          avatarMedia: avatarMedia,
          title: 'Space settings',
          onSaved: (details) {
            final savedName = details.name?.trim();
            _controller.updateSpaceDetails(
              spaceId: space.id,
              name: savedName == null || savedName.isEmpty
                  ? space.name
                  : savedName,
              description: details.topic?.trim() ?? '',
            );
          },
        ),
      ),
    );
  }

  Future<void> _openLinkRoom(BuildContext context) async {
    final coordinator = roomCreation;
    final space = _controller.selectedSpace;
    if (coordinator == null || space == null) return;
    final linkedRoomId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) =>
          _LinkRoomSheet(coordinator: coordinator, space: space),
    );
    if (linkedRoomId == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Room linked to ${space.name}. It will appear after the next sync.',
        ),
      ),
    );
  }

  Future<void> _openCreateRoom(BuildContext context) async {
    final coordinator = roomCreation;
    final space = _controller.selectedSpace;
    if (coordinator == null || space == null) return;
    final created = await Navigator.of(context).push<KiteCreatedRoom>(
      MaterialPageRoute<KiteCreatedRoom>(
        builder: (routeContext) => RoomCreationScreen(
          coordinator: coordinator,
          initialMode: RoomCreationMode.privateRoom,
          parentSpaceId: space.id,
          onCreated: (room) => Navigator.of(routeContext).pop(room),
        ),
      ),
    );
    if (created == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${created.displayName} created in ${space.name}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('spaces-screen'),
      backgroundColor: context.kiteColors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              key: const Key('spaces-header'),
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      key: const Key('spaces-back'),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: KiteSpacing.xs),
                    Expanded(
                      child: Text(
                        'Spaces',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (roomCreation != null) ...<Widget>[
                      IconButton(
                        key: const Key('spaces-link-room'),
                        tooltip: 'Link existing room to selected Space',
                        onPressed: () => _openLinkRoom(context),
                        icon: const Icon(Icons.link_rounded),
                      ),
                      IconButton(
                        key: const Key('spaces-manage'),
                        tooltip: 'Manage selected Space',
                        onPressed: () => _openManageSpace(context),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      IconButton(
                        key: const Key('spaces-create-room'),
                        tooltip: 'Create room in selected Space',
                        onPressed: () => _openCreateRoom(context),
                        icon: const Icon(Icons.add_box_outlined),
                      ),
                      IconButton(
                        key: const Key('spaces-create'),
                        tooltip: 'Create Space',
                        onPressed: () => _openCreateSpace(context),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  if (wide) {
                    return Row(
                      children: <Widget>[
                        SizedBox(
                          width: 264,
                          child: _SpaceRail(controller: _controller),
                        ),
                        VerticalDivider(width: 1, color: colors.outlineVariant),
                        Expanded(
                          child: _SelectedSpaceBody(
                            controller: _controller,
                            roomManagement: roomCreation,
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      _SpaceChipRow(controller: _controller),
                      Expanded(
                        child: _SelectedSpaceBody(
                          controller: _controller,
                          roomManagement: roomCreation,
                        ),
                      ),
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

class _SpaceChipRow extends StatelessWidget {
  const _SpaceChipRow({required this.controller});

  final SpacesController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('spaces-chip-row'),
      height: 64,
      child: SignalBuilder(
        builder: (context) {
          final selected = controller.selectedSpaceId.value;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: KiteSpacing.md,
              vertical: KiteSpacing.sm,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: controller.spaces.length,
            separatorBuilder: (_, _) => const SizedBox(width: KiteSpacing.xs),
            itemBuilder: (context, index) {
              final space = controller.spaces[index];
              return ChoiceChip(
                key: Key('spaces-chip-${space.id}'),
                selected: selected == space.id,
                showCheckmark: false,
                avatar: CircleAvatar(
                  child: Text(space.name.characters.first.toUpperCase()),
                ),
                label: Text(space.name),
                onSelected: (_) => controller.selectSpace(space.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _SpaceRail extends StatelessWidget {
  const _SpaceRail({required this.controller});

  final SpacesController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final selected = controller.selectedSpaceId.value;
        return ListView.builder(
          key: const Key('spaces-rail'),
          padding: const EdgeInsets.all(KiteSpacing.sm),
          itemCount: controller.spaces.length,
          itemExtent: 64,
          itemBuilder: (context, index) {
            final space = controller.spaces[index];
            final active = selected == space.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: KiteSpacing.xxs),
              child: Material(
                color: active
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(KiteRadii.md),
                child: InkWell(
                  key: Key('spaces-rail-${space.id}'),
                  onTap: () => controller.selectSpace(space.id),
                  borderRadius: BorderRadius.circular(KiteRadii.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KiteSpacing.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 18,
                          child: Text(
                            space.name.characters.first.toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: KiteSpacing.sm),
                        Expanded(
                          child: Text(
                            space.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
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
      },
    );
  }
}

final class _RoomManagementSpaceDirectoryPort implements SpaceDirectoryPort {
  const _RoomManagementSpaceDirectoryPort(this.coordinator);

  final RoomManagementCoordinator coordinator;

  @override
  Future<SpaceJoinOutcome> joinRoom({
    required String spaceId,
    required String roomId,
    required String joinRule,
  }) async {
    try {
      switch (joinRule) {
        case 'public':
        case 'restricted':
          await coordinator.joinRoomFromDirectory(roomId);
          return SpaceJoinOutcome.joined;
        case 'knock':
        case 'knock_restricted':
          await coordinator.requestRoomJoin(roomId);
          return SpaceJoinOutcome.requested;
        default:
          return SpaceJoinOutcome.failed;
      }
    } catch (_) {
      return SpaceJoinOutcome.failed;
    }
  }
}

class _SelectedSpaceBody extends StatefulWidget {
  const _SelectedSpaceBody({
    required this.controller,
    required this.roomManagement,
  });

  final SpacesController controller;
  final RoomManagementCoordinator? roomManagement;

  @override
  State<_SelectedSpaceBody> createState() => _SelectedSpaceBodyState();
}

class _SelectedSpaceBodyState extends State<_SelectedSpaceBody> {
  final Set<String> _loadedSpaceIds = <String>{};
  final Set<String> _loadingSpaceIds = <String>{};
  late void Function() _disposeSelectionEffect;
  int _selectionGeneration = 0;
  String? _hierarchyErrorSpaceId;

  @override
  void initState() {
    super.initState();
    _bindController();
  }

  @override
  void didUpdateWidget(_SelectedSpaceBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.roomManagement, widget.roomManagement)) {
      _disposeSelectionEffect();
      _loadedSpaceIds.clear();
      _loadingSpaceIds.clear();
      _bindController();
    }
  }

  void _bindController() {
    final coordinator = widget.roomManagement;
    if (coordinator != null &&
        widget.controller.spaces.every((space) => space.id.startsWith('!'))) {
      widget.controller.updateDirectoryPort(
        _RoomManagementSpaceDirectoryPort(coordinator),
      );
    }
    final generation = ++_selectionGeneration;
    _disposeSelectionEffect = effect(() {
      final spaceId = widget.controller.selectedSpaceId.value;
      if (spaceId == null) return;
      unawaited(
        Future<void>.microtask(() async {
          if (!mounted || generation != _selectionGeneration) return;
          await _loadHierarchy(spaceId);
        }),
      );
    });
  }

  Future<void> _loadHierarchy(String spaceId) async {
    final coordinator = widget.roomManagement;
    if (coordinator == null ||
        !spaceId.startsWith('!') ||
        _loadedSpaceIds.contains(spaceId) ||
        !_loadingSpaceIds.add(spaceId)) {
      return;
    }
    try {
      final hierarchy = await coordinator.loadSpaceHierarchy(spaceId);
      if (!mounted) return;
      if (hierarchy.isEmpty) {
        _loadedSpaceIds.add(spaceId);
        return;
      }
      KiteSpaceHierarchyEntry? root;
      for (final entry in hierarchy) {
        if (entry.roomId == spaceId) {
          root = entry;
          break;
        }
      }
      if (root == null) {
        throw StateError('Matrix Space hierarchy omitted the requested Space.');
      }
      final byId = <String, KiteSpaceHierarchyEntry>{
        for (final entry in hierarchy) entry.roomId: entry,
      };
      final current = widget.controller.spaceFor(spaceId);
      if (current == null) return;
      final childIds = <String>{...root.childRoomIds}..remove(spaceId);
      final childEntries = <KiteSpaceHierarchyEntry>[
        for (final childId in childIds) ?byId[childId],
      ];
      final joinedSpaceIds = widget.controller.spaces
          .map((space) => space.id)
          .toSet();
      widget.controller.reconcileHierarchy(
        spaceId: spaceId,
        rooms: <SpaceRoomPreview>[
          for (final child in childEntries)
            if (!child.isSpace)
              SpaceRoomPreview(
                id: child.roomId,
                name: _hierarchyName(child),
                topic: child.topic?.trim() ?? '',
                memberCount: child.joinedMembers,
                joinRule: child.joinRule,
                joined: current.rooms.any(
                  (room) => room.id == child.roomId && room.joined,
                ),
              ),
        ],
        childSpaces: <SpaceSummary>[
          for (final child in childEntries)
            if (child.isSpace)
              SpaceSummary(
                id: child.roomId,
                name: _hierarchyName(child),
                description: child.topic?.trim().isNotEmpty == true
                    ? child.topic!.trim()
                    : 'Matrix Space',
                memberCount: child.joinedMembers,
                rooms: const <SpaceRoomPreview>[],
                childSpaceIds: child.childRoomIds,
                external: !joinedSpaceIds.contains(child.roomId),
              ),
        ],
      );
      _loadedSpaceIds.add(spaceId);
      if (_hierarchyErrorSpaceId == spaceId && mounted) {
        setState(() => _hierarchyErrorSpaceId = null);
      }
    } catch (_) {
      if (mounted) setState(() => _hierarchyErrorSpaceId = spaceId);
    } finally {
      _loadingSpaceIds.remove(spaceId);
    }
  }

  String _hierarchyName(KiteSpaceHierarchyEntry entry) {
    final name = entry.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    final alias = entry.canonicalAlias?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    return entry.roomId;
  }

  @override
  void dispose() {
    _selectionGeneration++;
    _disposeSelectionEffect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return SignalBuilder(
      builder: (context) {
        final space = controller.selectedSpace;
        if (space == null) {
          return const Center(child: Text('No Spaces joined yet'));
        }
        final parentSpaces = controller.parentSpacesFor(space.id);
        final childSpaces = controller.childSpacesFor(space.id);
        return CustomScrollView(
          key: Key('space-body-${space.id}'),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KiteSpacing.lg,
                  KiteSpacing.lg,
                  KiteSpacing.lg,
                  KiteSpacing.sm,
                ),
                child: _SpaceHero(space: space),
              ),
            ),
            if (_hierarchyErrorSpaceId == space.id)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.lg,
                    vertical: KiteSpacing.xs,
                  ),
                  child: Row(
                    key: Key('space-hierarchy-error-${space.id}'),
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Kite could not browse this Space.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _loadedSpaceIds.remove(space.id);
                          unawaited(_loadHierarchy(space.id));
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (parentSpaces.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.lg,
                    KiteSpacing.xs,
                    KiteSpacing.lg,
                    KiteSpacing.sm,
                  ),
                  child: Wrap(
                    spacing: KiteSpacing.xs,
                    runSpacing: KiteSpacing.xs,
                    children: <Widget>[
                      for (final parent in parentSpaces)
                        TextButton.icon(
                          key: Key('space-parent-${parent.id}'),
                          onPressed: () => controller.selectSpace(parent.id),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                          ),
                          label: Text(parent.name),
                        ),
                    ],
                  ),
                ),
              ),
            if (childSpaces.isNotEmpty) ...<Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.lg,
                    KiteSpacing.md,
                    KiteSpacing.lg,
                    KiteSpacing.sm,
                  ),
                  child: Text(
                    'Spaces in this Space',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KiteSpacing.md,
                  0,
                  KiteSpacing.md,
                  KiteSpacing.sm,
                ),
                sliver: SliverList.builder(
                  itemCount: childSpaces.length,
                  itemBuilder: (context, index) => _NestedSpaceRow(
                    space: childSpaces[index],
                    onOpen: () => controller.selectSpace(childSpaces[index].id),
                  ),
                ),
              ),
            ],
            if (space.rooms.isNotEmpty) ...<Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.lg,
                    KiteSpacing.md,
                    KiteSpacing.lg,
                    KiteSpacing.sm,
                  ),
                  child: Text(
                    'Rooms in this Space',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KiteSpacing.md,
                  0,
                  KiteSpacing.md,
                  KiteSpacing.lg,
                ),
                sliver: SliverList.builder(
                  itemCount: space.rooms.length,
                  itemBuilder: (context, index) => _SpaceRoomRow(
                    space: space,
                    room: space.rooms[index],
                    controller: controller,
                    roomManagement: widget.roomManagement,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NestedSpaceRow extends StatelessWidget {
  const _NestedSpaceRow({required this.space, required this.onOpen});

  final SpaceSummary space;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: Key('nested-space-row-${space.id}'),
      height: 72,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KiteRadii.md),
        child: InkWell(
          key: Key('nested-space-open-${space.id}'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(KiteRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: Text(space.name.characters.first.toUpperCase()),
                ),
                const SizedBox(width: KiteSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        space.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${KiteLocalFormats.decimal(context, space.memberCount)} members',
                        style: KiteTypography.metadata.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceHero extends StatelessWidget {
  const _SpaceHero({required this.space});

  final SpaceSummary space;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          key: Key('space-avatar-${space.id}'),
          radius: 30,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(
            space.name.characters.first.toUpperCase(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: KiteSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      space.name,
                      key: Key('space-title-${space.id}'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (space.external)
                    const Tooltip(
                      message: 'External Space',
                      child: Icon(Icons.public_rounded, size: 19),
                    ),
                ],
              ),
              const SizedBox(height: KiteSpacing.xs),
              Text(
                space.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KiteSpacing.xs),
              Text(
                space.rooms.isEmpty
                    ? '${KiteLocalFormats.decimal(context, space.memberCount)} members'
                    : '${KiteLocalFormats.decimal(context, space.memberCount)} members · '
                          '${KiteLocalFormats.decimal(context, space.rooms.length)} rooms',
                style: KiteTypography.metadata.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpaceRoomRow extends StatelessWidget {
  const _SpaceRoomRow({
    required this.space,
    required this.room,
    required this.controller,
    required this.roomManagement,
  });

  final SpaceSummary space;
  final SpaceRoomPreview room;
  final SpacesController controller;
  final RoomManagementCoordinator? roomManagement;

  Future<void> _unlink(BuildContext context) async {
    final coordinator = roomManagement;
    if (coordinator == null) return;
    try {
      await coordinator.setSpaceChild(
        spaceId: space.id,
        roomId: room.id,
        linked: false,
      );
      controller.removeRoomFromSpace(spaceId: space.id, roomId: room.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${room.name} removed from ${space.name}')),
      );
    } on RoomManagementValidationException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kite could not unlink that room.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: Key('space-room-row-${room.id}'),
      height: 80,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KiteRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 21,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Text(room.name.characters.first.toUpperCase()),
              ),
              const SizedBox(width: KiteSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      room.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${KiteLocalFormats.decimal(context, room.memberCount)} members',
                      style: KiteTypography.metadata.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KiteSpacing.sm),
              SizedBox(
                key: Key('space-room-action-slot-${room.id}'),
                width: 92,
                height: 44,
                child: SignalBuilder(
                  builder: (context) {
                    final state = controller.joinStateFor(room.id).value;
                    return switch (state) {
                      SpaceRoomJoinState.joined =>
                        roomManagement == null
                            ? Center(
                                child: Text(
                                  'Joined',
                                  key: Key('space-room-joined-${room.id}'),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : OutlinedButton(
                                key: Key('space-room-unlink-${room.id}'),
                                onPressed: () => _unlink(context),
                                child: const Text('Remove'),
                              ),
                      SpaceRoomJoinState.requested => Center(
                        child: Text(
                          'Requested',
                          key: Key('space-room-requested-${room.id}'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SpaceRoomJoinState.joining => const Center(
                        child: SizedBox.square(
                          key: Key('space-room-joining'),
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      SpaceRoomJoinState.failed => OutlinedButton(
                        key: Key('space-room-retry-${room.id}'),
                        onPressed: () => controller.joinRoom(
                          spaceId: space.id,
                          roomId: room.id,
                        ),
                        child: const Text('Retry'),
                      ),
                      SpaceRoomJoinState.idle => switch (room.joinRule) {
                        'public' || 'restricted' => FilledButton.tonal(
                          key: Key('space-room-join-${room.id}'),
                          onPressed: () => controller.joinRoom(
                            spaceId: space.id,
                            roomId: room.id,
                          ),
                          child: const Text('Join'),
                        ),
                        'knock' || 'knock_restricted' => FilledButton.tonal(
                          key: Key('space-room-request-${room.id}'),
                          onPressed: () => controller.joinRoom(
                            spaceId: space.id,
                            roomId: room.id,
                          ),
                          child: const Text('Request'),
                        ),
                        _ => Center(
                          child: Text(
                            'Invite only',
                            key: Key('space-room-invite-only-${room.id}'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      },
                    };
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkRoomSheet extends StatefulWidget {
  const _LinkRoomSheet({required this.coordinator, required this.space});

  final RoomManagementCoordinator coordinator;
  final SpaceSummary space;

  @override
  State<_LinkRoomSheet> createState() => _LinkRoomSheetState();
}

class _LinkRoomSheetState extends State<_LinkRoomSheet> {
  final TextEditingController _roomId = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _roomId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final roomId = _roomId.text.trim();
      await widget.coordinator.setSpaceChild(
        spaceId: widget.space.id,
        roomId: roomId,
        linked: true,
      );
      if (mounted) Navigator.of(context).pop(roomId);
    } on RoomManagementValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kite could not link that room to the Space.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.lg,
        KiteSpacing.lg,
        KiteSpacing.lg + bottomInset,
      ),
      child: Column(
        key: const Key('space-link-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Link room to ${widget.space.name}',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: KiteSpacing.xs),
          Text(
            'Enter the Matrix room ID for a room you have already joined.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KiteSpacing.md),
          TextField(
            key: const Key('space-link-room-id'),
            controller: _roomId,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Matrix room ID',
              hintText: '!room:example.org',
              errorText: _error,
            ),
          ),
          const SizedBox(height: KiteSpacing.md),
          FilledButton.icon(
            key: const Key('space-link-submit'),
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            label: const Text('Link room'),
          ),
        ],
      ),
    );
  }
}

class _CreateSpaceSheet extends StatefulWidget {
  const _CreateSpaceSheet({required this.coordinator});

  final RoomManagementCoordinator coordinator;

  @override
  State<_CreateSpaceSheet> createState() => _CreateSpaceSheetState();
}

class _CreateSpaceSheetState extends State<_CreateSpaceSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _topic = TextEditingController();
  bool _isPublic = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await widget.coordinator.createSpace(
        name: _name.text,
        topic: _topic.text,
        isPublic: _isPublic,
      );
      if (mounted) Navigator.of(context).pop(created);
    } on RoomManagementValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kite could not create the Space.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        KiteSpacing.lg,
        KiteSpacing.lg,
        KiteSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Create Space',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: KiteSpacing.md),
            TextField(
              key: const Key('space-create-name'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: KiteSpacing.sm),
            TextField(
              key: const Key('space-create-topic'),
              controller: _topic,
              decoration: const InputDecoration(labelText: 'Topic (optional)'),
            ),
            const SizedBox(height: KiteSpacing.sm),
            SwitchListTile.adaptive(
              key: const Key('space-create-public'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Public Space'),
              subtitle: const Text('Anyone can discover and join'),
              value: _isPublic,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _isPublic = value),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: KiteSpacing.xs),
              Text(
                error,
                key: const Key('space-create-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: KiteSpacing.md),
            FilledButton(
              key: const Key('space-create-submit'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Space'),
            ),
          ],
        ),
      ),
    );
  }
}
