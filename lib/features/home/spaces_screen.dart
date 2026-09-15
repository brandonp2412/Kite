import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:signals/signals_flutter.dart';

class SpacesRoute extends PageRouteBuilder<void> {
  SpacesRoute({required bool reduceMotion, SpacesController? controller})
    : super(
        transitionDuration: reduceMotion ? Duration.zero : KiteMotion.standard,
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : KiteMotion.standard,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SpacesScreen(controller: controller),
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
  const SpacesScreen({super.key, this.controller});

  final SpacesController? controller;

  SpacesController get _controller => controller ?? spacesController;

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
                          child: _SelectedSpaceBody(controller: _controller),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      _SpaceChipRow(controller: _controller),
                      Expanded(
                        child: _SelectedSpaceBody(controller: _controller),
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

class _SelectedSpaceBody extends StatelessWidget {
  const _SelectedSpaceBody({required this.controller});

  final SpacesController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final space = controller.selectedSpace;
        if (space == null) {
          return const Center(child: Text('No Spaces joined yet'));
        }
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
                ),
              ),
            ),
          ],
        );
      },
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
                '${space.memberCount} members · ${space.rooms.length} rooms',
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
  });

  final SpaceSummary space;
  final SpaceRoomPreview room;
  final SpacesController controller;

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
                      '${room.memberCount} members',
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
                      SpaceRoomJoinState.joined => Center(
                        child: Text(
                          'Joined',
                          key: Key('space-room-joined-${room.id}'),
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
                      SpaceRoomJoinState.idle => FilledButton.tonal(
                        key: Key('space-room-join-${room.id}'),
                        onPressed: () => controller.joinRoom(
                          spaceId: space.id,
                          roomId: room.id,
                        ),
                        child: const Text('Join'),
                      ),
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
