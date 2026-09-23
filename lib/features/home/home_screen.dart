import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderSliver, ScrollCacheExtent;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/jitter_injector.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/authenticated_account_scope.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/encryption_recovery_screen.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/rooms/room_creation_screen.dart';
import 'package:kite/features/rooms/room_details_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';
import 'package:kite/features/media/room_content_gallery.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/features/timeline/timeline_location_card.dart';
import 'package:kite/features/timeline/timeline_location_share_sheet.dart';
import 'package:kite/features/timeline/timeline_message_body.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:kite/features/timeline/timeline_poll_card.dart';
import 'package:kite/features/timeline/timeline_poll_sheet.dart';
import 'package:kite/l10n/kite_localizations.dart';
import 'package:signals/signals_flutter.dart';

typedef TimelineHistoryRequest = Future<void> Function(
  String roomId,
  int oldestVisibleIndex,
);
typedef RoomMembersLoader = Future<RoomMembersStore> Function(String roomId);
typedef RoomFavouriteChange = Future<void> Function(
  String roomId,
  bool isFavourite,
);
typedef MarkRoomRead = Future<void> Function(String roomId);
typedef MarkAllRoomsRead = Future<void> Function();

bool _isDesktopPlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
}

RelativeRect _popupPosition(BuildContext context, Offset position) {
  final size = MediaQuery.sizeOf(context);
  return RelativeRect.fromLTRB(
    position.dx,
    position.dy,
    size.width - position.dx,
    size.height - position.dy,
  );
}

Future<T?> _adaptiveSurface<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool scroll = false,
}) {
  if (_isDesktopPlatform(context)) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.84,
          ),
          child: builder(dialogContext),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: scroll,
    constraints: const BoxConstraints(maxWidth: 440),
    builder: builder,
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.benchmarkRooms,
    this.roomListStore,
    this.inviteStore,
    this.roomCreation,
    this.roomManagement,
    this.memberManagement,
    this.calls,
    this.timeline,
    this.onTimelineHistoryRequested,
    this.onRoomFavouriteChanged,
    this.onMarkRoomRead,
    this.onMarkAllRoomsRead,
    this.profileAvatarPicker,
    this.profileAvatarImageProvider,
    this.profileAvatarFallbackUri,
    this.recentPeople = const <KiteUserSearchResult>[],
    this.timelineMediaImageProvider,
    this.roomListLoading = false,
    this.timelineReloading = false,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final List<BenchmarkRoom>? benchmarkRooms;
  final RoomListStateStore? roomListStore;
  final RoomInviteStore? inviteStore;
  final RoomManagementCoordinator? roomCreation;
  final RoomManagementCoordinator? roomManagement;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final KiteCallCoordinator? calls;
  final TimelineController? timeline;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final RoomFavouriteChange? onRoomFavouriteChanged;
  final MarkRoomRead? onMarkRoomRead;
  final MarkAllRoomsRead? onMarkAllRoomsRead;
  final AvatarPicker? profileAvatarPicker;
  final AvatarImageProvider? profileAvatarImageProvider;
  final Uri? profileAvatarFallbackUri;
  final List<KiteUserSearchResult> recentPeople;
  final TimelineMediaImageProvider? timelineMediaImageProvider;
  final bool roomListLoading;
  final bool timelineReloading;
  final RoomMembersLoader? roomMembersLoader;
  final bool memberModerationEnabled;

  static const double sidebarWidth = 320;
  static const double tabletSidebarWidth = 300;
  static const double phoneBreakpoint = 600;

  void _selectRoom(String roomId) {
    selectRoom(roomId);
    final markRoomRead = onMarkRoomRead;
    if (markRoomRead != null) unawaited(markRoomRead(roomId));
  }

  Future<void> _jumpToChat(
    BuildContext context,
    List<RoomListEntry> fallbackRooms,
  ) async {
    final store = roomListStore;
    final rooms = store == null
        ? fallbackRooms
        : <RoomListEntry>[
            for (final roomId in store.roomIds) store.roomSignal(roomId).peek(),
          ];
    final roomId = await showDialog<String>(
      context: context,
      builder: (_) => _ChatJumpDialog(
        rooms: rooms,
        avatarImageProvider: profileAvatarImageProvider,
      ),
    );
    if (roomId != null) _selectRoom(roomId);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < phoneBreakpoint;
    final homeTimeline = timeline ?? timelineController;
    final roomEntries = roomListStore == null
        ? deterministicRoomListEntries(benchmarkRooms ?? BenchmarkFixture.rooms)
        : const <RoomListEntry>[];

    if (isPhone) {
      return _HomeTimelineControllerScope(
        controller: homeTimeline,
        roomListStore: roomListStore,
        avatarImageProvider: profileAvatarImageProvider,
        timelineMediaImageProvider: timelineMediaImageProvider,
        timelineHistoryRequest: onTimelineHistoryRequested,
        child: Scaffold(
          body: SafeArea(
            child: SizedBox.expand(
              key: const Key('sidebar'),
              child: _HomeSidebar(
                rooms: roomEntries,
                store: roomListStore,
                inviteStore: inviteStore,
                roomCreation: roomCreation,
                onRoomFavouriteChanged: onRoomFavouriteChanged,
                onMarkAllRoomsRead: onMarkAllRoomsRead,
                profileAvatarPicker: profileAvatarPicker,
                profileAvatarImageProvider: profileAvatarImageProvider,
                profileAvatarFallbackUri: profileAvatarFallbackUri,
                recentPeople: recentPeople,
                roomListLoading: roomListLoading,
                onRoomTap: (roomId) {
                  _selectRoom(roomId);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CompactChatScreen(
                        timeline: homeTimeline,
                        roomListStore: roomListStore,
                        avatarImageProvider: profileAvatarImageProvider,
                        timelineMediaImageProvider: timelineMediaImageProvider,
                        roomManagement: roomManagement,
                        memberManagement: memberManagement,
                        calls: calls,
                        onTimelineHistoryRequested: onTimelineHistoryRequested,
                        timelineReloading: timelineReloading,
                        roomMembersLoader: roomMembersLoader,
                        memberModerationEnabled: memberModerationEnabled,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    final adaptiveSidebarWidth = size.width < 1024
        ? tabletSidebarWidth
        : sidebarWidth;
    return _HomeTimelineControllerScope(
      controller: homeTimeline,
      roomListStore: roomListStore,
      avatarImageProvider: profileAvatarImageProvider,
      timelineMediaImageProvider: timelineMediaImageProvider,
      timelineHistoryRequest: onTimelineHistoryRequested,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            unawaited(_jumpToChat(context, roomEntries));
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: <Widget>[
                SizedBox(
                  key: const Key('sidebar'),
                  width: adaptiveSidebarWidth,
                  child: _HomeSidebar(
                    rooms: roomEntries,
                    store: roomListStore,
                    inviteStore: inviteStore,
                    roomCreation: roomCreation,
                    onRoomFavouriteChanged: onRoomFavouriteChanged,
                    onMarkAllRoomsRead: onMarkAllRoomsRead,
                    profileAvatarPicker: profileAvatarPicker,
                    profileAvatarImageProvider: profileAvatarImageProvider,
                    profileAvatarFallbackUri: profileAvatarFallbackUri,
                    recentPeople: recentPeople,
                    roomListLoading: roomListLoading,
                    onRoomTap: _selectRoom,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: RepaintBoundary(
                    child: _ChatPanel(
                      roomListStore: roomListStore,
                      roomManagement: roomManagement,
                      memberManagement: memberManagement,
                      calls: calls,
                      onTimelineHistoryRequested: onTimelineHistoryRequested,
                      timelineReloading: timelineReloading,
                      roomMembersLoader: roomMembersLoader,
                      memberModerationEnabled: memberModerationEnabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatJumpDialog extends StatefulWidget {
  const _ChatJumpDialog({
    required this.rooms,
    required this.avatarImageProvider,
  });

  final List<RoomListEntry> rooms;
  final AvatarImageProvider? avatarImageProvider;

  @override
  State<_ChatJumpDialog> createState() => _ChatJumpDialogState();
}

class _ChatJumpDialogState extends State<_ChatJumpDialog> {
  String _query = '';

  List<RoomListEntry> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.rooms.take(12).toList(growable: false);
    return widget.rooms
        .where(
          (room) =>
              room.name.toLowerCase().contains(query) ||
              room.latestEventBody.toLowerCase().contains(query) ||
              (room.latestSender?.toLowerCase().contains(query) ?? false),
        )
        .take(12)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return AlertDialog(
      key: const Key('chat-jump-dialog'),
      title: const Text('Jump to chat'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: <Widget>[
            TextField(
              key: const Key('chat-jump-search'),
              autofocus: true,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                hintText: 'Search chats',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.isNotEmpty) {
                  Navigator.of(context).pop(matches.first.id);
                }
              },
            ),
            const SizedBox(height: KiteSpacing.sm),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final room = matches[index];
                  final avatarUri = Uri.tryParse(room.avatarUrl ?? '');
                  final image = avatarUri?.scheme == 'mxc'
                      ? widget.avatarImageProvider?.call(avatarUri)
                      : null;
                  return ListTile(
                    key: Key('chat-jump-${room.id}'),
                    leading: CircleAvatar(
                      backgroundImage: image,
                      child: image == null
                          ? Text(room.name.characters.first.toUpperCase())
                          : null,
                    ),
                    title: Text(room.name),
                    subtitle: Text(
                      room.latestEventBody,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(room.id),
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

class _HomeTimelineControllerScope extends InheritedWidget {
  const _HomeTimelineControllerScope({
    required this.controller,
    required this.roomListStore,
    required this.avatarImageProvider,
    required this.timelineMediaImageProvider,
    required this.timelineHistoryRequest,
    required super.child,
  });

  final TimelineController controller;
  final RoomListStateStore? roomListStore;
  final AvatarImageProvider? avatarImageProvider;
  final TimelineMediaImageProvider? timelineMediaImageProvider;
  final TimelineHistoryRequest? timelineHistoryRequest;

  static TimelineController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_HomeTimelineControllerScope>();
    if (scope == null) {
      throw StateError('Home timeline controller scope is missing.');
    }
    return scope.controller;
  }

  static RoomListStateStore? roomListStoreOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_HomeTimelineControllerScope>()
        ?.roomListStore;
  }

  static AvatarImageProvider? avatarImageProviderOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_HomeTimelineControllerScope>()
        ?.avatarImageProvider;
  }

  static TimelineMediaImageProvider? timelineMediaImageProviderOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<_HomeTimelineControllerScope>()
        ?.timelineMediaImageProvider;
  }

  static TimelineHistoryRequest? timelineHistoryRequestOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<_HomeTimelineControllerScope>()
        ?.timelineHistoryRequest;
  }

  @override
  bool updateShouldNotify(_HomeTimelineControllerScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(roomListStore, oldWidget.roomListStore) ||
      !identical(avatarImageProvider, oldWidget.avatarImageProvider) ||
      !identical(
        timelineMediaImageProvider,
        oldWidget.timelineMediaImageProvider,
      ) ||
      !identical(timelineHistoryRequest, oldWidget.timelineHistoryRequest);
}

TimelineController _homeTimelineController(BuildContext context) =>
    _HomeTimelineControllerScope.of(context);

RoomListStateStore? _homeRoomListStore(BuildContext context) =>
    _HomeTimelineControllerScope.roomListStoreOf(context);

AvatarImageProvider? _homeAvatarImageProvider(BuildContext context) =>
    _HomeTimelineControllerScope.avatarImageProviderOf(context);

TimelineMediaImageProvider? _homeTimelineMediaImageProvider(
  BuildContext context,
) => _HomeTimelineControllerScope.timelineMediaImageProviderOf(context);

class _HomeSidebar extends StatefulWidget {
  const _HomeSidebar({
    required this.rooms,
    this.store,
    this.inviteStore,
    this.roomCreation,
    this.onRoomFavouriteChanged,
    this.onMarkAllRoomsRead,
    this.profileAvatarPicker,
    this.profileAvatarImageProvider,
    this.profileAvatarFallbackUri,
    this.recentPeople = const <KiteUserSearchResult>[],
    this.roomListLoading = false,
    this.onRoomTap,
  });

  final List<RoomListEntry> rooms;
  final RoomListStateStore? store;
  final RoomInviteStore? inviteStore;
  final RoomManagementCoordinator? roomCreation;
  final RoomFavouriteChange? onRoomFavouriteChanged;
  final MarkAllRoomsRead? onMarkAllRoomsRead;
  final AvatarPicker? profileAvatarPicker;
  final AvatarImageProvider? profileAvatarImageProvider;
  final Uri? profileAvatarFallbackUri;
  final List<KiteUserSearchResult> recentPeople;
  final bool roomListLoading;
  final ValueChanged<String>? onRoomTap;

  @override
  State<_HomeSidebar> createState() => _HomeSidebarState();
}

class _HomeSidebarState extends State<_HomeSidebar> {
  RoomListStateStore? _ownedStore;
  RoomInviteStore? _ownedInviteStore;
  final TextEditingController _searchController = TextEditingController();
  final List<void Function()> _disposeThreadUnreadEffects = <void Function()>[];
  String _searchQuery = '';
  UserProfileController? _loadedProfileController;

  RoomListStateStore get store => widget.store ?? _ownedStore!;
  RoomInviteStore get inviteStore => widget.inviteStore ?? _ownedInviteStore!;

  @override
  void initState() {
    super.initState();
    if (widget.store == null) {
      _ownedStore = RoomListStateStore(widget.rooms);
    }
    if (widget.inviteStore == null) {
      _ownedInviteStore = RoomInviteStore(deterministicRoomInvites);
    }
    _bindThreadUnreadState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AuthenticatedAccountScope.maybeOf(context)
        ?.profileController;
    if (identical(controller, _loadedProfileController)) return;
    _loadedProfileController = controller;
    if (controller != null &&
        controller.ownProfile.peek() == null &&
        !controller.isLoading.peek()) {
      unawaited(controller.loadOwnProfile());
    }
  }

  @override
  void didUpdateWidget(covariant _HomeSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _clearThreadUnreadEffects();
      if (widget.store == null) {
        _ownedStore ??= RoomListStateStore(widget.rooms);
      } else {
        _ownedStore = null;
      }
      _bindThreadUnreadState();
    }
    if (oldWidget.inviteStore != widget.inviteStore) {
      if (widget.inviteStore == null) {
        _ownedInviteStore ??= RoomInviteStore(deterministicRoomInvites);
      } else {
        _ownedInviteStore = null;
      }
    }
  }

  void _bindThreadUnreadState() {
    for (final roomId in store.roomIds) {
      _disposeThreadUnreadEffects.add(
        effect(() {
          final unreadThreadCount = threadController
              .unreadThreadCountForRoom(roomId)
              .value;
          final roomSignal = store.roomSignal(roomId);
          final room = roomSignal.peek();
          if (room.unreadThreadCount == unreadThreadCount) return;
          store.update(room.copyWith(unreadThreadCount: unreadThreadCount));
        }),
      );
    }
  }

  void _clearThreadUnreadEffects() {
    for (final dispose in _disposeThreadUnreadEffects) {
      dispose();
    }
    _disposeThreadUnreadEffects.clear();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _clearThreadUnreadEffects();
    super.dispose();
  }

  Future<void> _openAccountMenu(AuthenticatedAccountScope account) async {
    final action = await _adaptiveSurface<_HomeAccountAction>(
      context,
      (_) => _HomeAccountSheet(
        session: account.session,
        canOpenProfile: account.profileController != null,
        canOpenRecovery: account.recoveryController != null,
        inviteCount: inviteStore.visibleInviteIds.value.length,
        profileController: account.profileController,
        avatarImageProvider: widget.profileAvatarImageProvider,
        fallbackAvatarUri: widget.profileAvatarFallbackUri,
      ),
    );
    if (!mounted || action == null) return;
    if (action == _HomeAccountAction.profile) {
      final controller = account.profileController;
      if (controller == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen.own(
            controller: controller,
            pickAvatar: widget.profileAvatarPicker,
            avatarImageProvider: widget.profileAvatarImageProvider,
            fallbackProfile:
                controller.ownProfile.peek() ??
                MatrixUserProfile(
                  userId: account.session.userId,
                  displayName: account.session.userId,
                  avatarUri: widget.profileAvatarFallbackUri,
                ),
            loadOnInit:
                controller.ownProfile.peek() == null &&
                !controller.isLoading.peek(),
          ),
        ),
      );
      return;
    }
    if (action == _HomeAccountAction.encryptionRecovery) {
      final controller = account.recoveryController;
      if (controller == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EncryptionRecoveryScreen(controller: controller),
        ),
      );
      return;
    }
    if (action == _HomeAccountAction.invites) {
      await _openInvitesSheet();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out from this device?'),
        content: const Text(
          'This signs out this Kite session and removes its local account data from this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('home-account-sign-out-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await account.signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Kite could not safely prepare this account for sign out.',
            ),
          ),
        );
    }
  }

  Future<void> _openRoomCreation({
    RoomCreationMode initialMode = RoomCreationMode.directMessage,
  }) async {
    final coordinator = widget.roomCreation;
    if (coordinator == null) return;
    final created = await Navigator.of(context).push<KiteCreatedRoom>(
      MaterialPageRoute<KiteCreatedRoom>(
        builder: (routeContext) => RoomCreationScreen(
          coordinator: coordinator,
          initialMode: initialMode,
          recentPeople: widget.recentPeople,
          onCreated: (room) => Navigator.of(routeContext).pop(room),
        ),
      ),
    );
    if (!mounted || created == null) return;

    store.addPendingRoom(
      RoomListEntry(
        id: created.roomId,
        name: created.displayName,
        latestEventBody: '',
        isDirect: created.isDirect,
        isPendingSync: true,
      ),
    );
    _searchController.clear();
    setState(() => _searchQuery = '');

    final handler = widget.onRoomTap;
    if (handler != null) {
      handler(created.roomId);
    } else {
      selectRoom(created.roomId);
    }
  }

  Future<void> _openInvitesSheet() async {
    await _adaptiveSurface<void>(
      context,
      (_) => _RoomInvitesSheet(store: inviteStore),
      scroll: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = AuthenticatedAccountScope.maybeOf(context);
    final canCreateRoom = widget.roomCreation != null;
    final searchField = TextField(
      key: const Key('home-search'),
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search chats',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: account == null && _searchQuery.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      key: const Key('home-search-clear'),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  if (account != null)
                    IconButton(
                      key: const Key('home-account-menu'),
                      tooltip: 'Account',
                      padding: EdgeInsets.zero,
                      onPressed: () => _openAccountMenu(account),
                      icon: _AccountAvatar(
                        session: account.session,
                        controller: account.profileController,
                        imageProvider: widget.profileAvatarImageProvider,
                        fallbackAvatarUri: widget.profileAvatarFallbackUri,
                        radius: 20,
                      ),
                    ),
                ],
              ),
        suffixIconConstraints: const BoxConstraints(minHeight: 48),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiteRadii.lg),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: KiteStroke.emphasis,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KiteSpacing.md,
          vertical: KiteSpacing.md,
        ),
      ),
      onChanged: (value) => setState(() => _searchQuery = value),
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: _RoomList(
            key: ValueKey<String>(_searchQuery),
            store: store,
            onRoomFavouriteChanged: widget.onRoomFavouriteChanged,
            onRoomTap: widget.onRoomTap,
            query: _searchQuery,
            roomListLoading: widget.roomListLoading,
            onCreateRoom: canCreateRoom
                ? () => _openRoomCreation(
                    initialMode: RoomCreationMode.privateRoom,
                  )
                : null,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KiteSpacing.md,
              KiteSpacing.sm,
              KiteSpacing.md,
              KiteSpacing.md,
            ),
            child: searchField,
          ),
        ),
      ],
    );
  }
}

enum _HomeAccountAction { profile, encryptionRecovery, invites, signOut }

class _HomeAccountSheet extends StatelessWidget {
  const _HomeAccountSheet({
    required this.session,
    required this.canOpenProfile,
    required this.canOpenRecovery,
    required this.inviteCount,
    this.profileController,
    this.avatarImageProvider,
    this.fallbackAvatarUri,
  });

  final AuthenticatedSession session;
  final bool canOpenProfile;
  final bool canOpenRecovery;
  final int inviteCount;
  final UserProfileController? profileController;
  final AvatarImageProvider? avatarImageProvider;
  final Uri? fallbackAvatarUri;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.lg,
          0,
          KiteSpacing.lg,
          KiteSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                key: canOpenProfile ? const Key('home-account-profile') : null,
                contentPadding: EdgeInsets.zero,
                leading: _AccountAvatar(
                  session: session,
                  controller: profileController,
                  imageProvider: avatarImageProvider,
                  radius: 20,
                ),
                title: Text(
                  session.userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Signed in on ${session.homeserver.uri.host}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: canOpenProfile
                    ? const Icon(Icons.chevron_right_rounded)
                    : null,
                onTap: canOpenProfile
                    ? () =>
                          Navigator.of(context).pop(_HomeAccountAction.profile)
                    : null,
              ),
              const Divider(height: KiteSpacing.lg),
              if (canOpenRecovery)
                ListTile(
                  key: const Key('home-account-encryption-recovery'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Encryption recovery'),
                  subtitle: const Text('Restore encrypted message history'),
                  onTap: () =>
                      Navigator.of(context)
                          .pop(_HomeAccountAction.encryptionRecovery),
                ),
              if (inviteCount > 0)
                ListTile(
                  key: const Key('home-account-invites'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: const Text('Invites'),
                  trailing: Text('$inviteCount'),
                  onTap: () =>
                      Navigator.of(context).pop(_HomeAccountAction.invites),
                ),
              ListTile(
                key: const Key('home-account-sign-out'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                onTap: () =>
                    Navigator.of(context).pop(_HomeAccountAction.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomInvitesSheet extends StatelessWidget {
  const _RoomInvitesSheet({required this.store});

  final RoomInviteStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        key: const Key('room-invites-sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.lg,
            0,
            KiteSpacing.lg,
            KiteSpacing.lg,
          ),
          child: SignalBuilder(
            builder: (context) {
              final ids = store.visibleInviteIds.value;
              if (ids.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: KiteSpacing.xl),
                  child: Center(child: Text('No pending invites')),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Invites', style: theme.textTheme.titleLarge),
                  const SizedBox(height: KiteSpacing.sm),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: ids.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: KiteSpacing.sm),
                      itemBuilder: (context, index) {
                        final inviteId = ids[index];
                        final invite = store.invite(inviteId);
                        final state = store.stateSignal(inviteId).value;
                        final pending =
                            state == RoomInviteActionState.accepting ||
                            state == RoomInviteActionState.declining;
                        final memberLabel = invite.memberCount == 1
                            ? '1 member'
                            : '${invite.memberCount} members';
                        final details = <String>[
                          'Invited by ${invite.inviterName}',
                          memberLabel,
                          if (invite.description != null) invite.description!,
                        ];
                        return Card(
                          key: Key('invite-$inviteId'),
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(KiteSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(
                                  invite.roomName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: KiteSpacing.xs),
                                Text(
                                  details.join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (state == RoomInviteActionState.failed)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: KiteSpacing.sm,
                                    ),
                                    child: Text(
                                      'Could not update this invite. Try again.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.error,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: KiteSpacing.md),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    TextButton(
                                      key: Key('invite-decline-$inviteId'),
                                      onPressed: pending
                                          ? null
                                          : () => store.decline(inviteId),
                                      child:
                                          state ==
                                              RoomInviteActionState.declining
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Decline'),
                                    ),
                                    const SizedBox(width: KiteSpacing.sm),
                                    FilledButton(
                                      key: Key('invite-accept-$inviteId'),
                                      onPressed: pending
                                          ? null
                                          : () => store.accept(inviteId),
                                      child:
                                          state ==
                                              RoomInviteActionState.accepting
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Accept'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _accountInitial(String userId) {
  final trimmed = userId.trim();
  if (trimmed.length > 1 && trimmed.startsWith('@')) {
    return trimmed[1].toUpperCase();
  }
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.session,
    required this.controller,
    required this.imageProvider,
    this.fallbackAvatarUri,
    required this.radius,
  });

  final AuthenticatedSession session;
  final UserProfileController? controller;
  final AvatarImageProvider? imageProvider;
  final Uri? fallbackAvatarUri;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final profileController = controller;
    if (profileController == null) {
      return _AvatarCircle(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        image: fallbackAvatarUri == null
            ? null
            : imageProvider?.call(fallbackAvatarUri!),
        fallback: Text(_accountInitial(session.userId)),
      );
    }
    return SignalBuilder(
      builder: (context) {
        final avatarUri =
            profileController.ownProfile.value?.avatarUri ?? fallbackAvatarUri;
        return _AvatarCircle(
          key: const Key('home-account-avatar'),
          radius: radius,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          image: avatarUri == null ? null : imageProvider?.call(avatarUri),
          fallback: Text(_accountInitial(session.userId)),
        );
      },
    );
  }
}

class _CompactChatScreen extends StatelessWidget {
  const _CompactChatScreen({
    required this.timeline,
    this.roomListStore,
    this.avatarImageProvider,
    this.timelineMediaImageProvider,
    this.roomManagement,
    this.memberManagement,
    this.calls,
    this.onTimelineHistoryRequested,
    this.timelineReloading = false,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final TimelineController timeline;
  final RoomListStateStore? roomListStore;
  final AvatarImageProvider? avatarImageProvider;
  final TimelineMediaImageProvider? timelineMediaImageProvider;
  final RoomManagementCoordinator? roomManagement;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final KiteCallCoordinator? calls;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final bool timelineReloading;
  final RoomMembersLoader? roomMembersLoader;
  final bool memberModerationEnabled;

  @override
  Widget build(BuildContext context) {
    return _HomeTimelineControllerScope(
      controller: timeline,
      roomListStore: roomListStore,
      avatarImageProvider: avatarImageProvider,
      timelineMediaImageProvider: timelineMediaImageProvider,
      timelineHistoryRequest: onTimelineHistoryRequested,
      child: Scaffold(
        key: const Key('compact-chat-screen'),
        appBar: AppBar(
          title: SignalBuilder(
            builder: (context) {
              final roomId = selectedRoomId.value;
              final store = roomListStore;
              if (store != null) {
                if (!store.roomIds.contains(roomId)) {
                  return const Text('Select a room');
                }
                return Text(store.roomSignal(roomId).value.name);
              }
              return Text(BenchmarkFixture.room(roomId).name);
            },
          ),
        ),
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _ChatPanel(
                showHeader: false,
                roomListStore: roomListStore,
                roomManagement: roomManagement,
                memberManagement: memberManagement,
                calls: calls,
                onTimelineHistoryRequested: onTimelineHistoryRequested,
                timelineReloading: timelineReloading,
                roomMembersLoader: roomMembersLoader,
                memberModerationEnabled: memberModerationEnabled,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: _CompactChatEdgeSwipe(
                onDismiss: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChatEdgeSwipe extends StatefulWidget {
  const _CompactChatEdgeSwipe({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<_CompactChatEdgeSwipe> createState() => _CompactChatEdgeSwipeState();
}

class _CompactChatEdgeSwipeState extends State<_CompactChatEdgeSwipe> {
  static const double _dismissDistance = 72;
  static const double _dismissVelocity = 600;

  double _dragDistance = 0;

  void _handleDragStart(DragStartDetails details) {
    _dragDistance = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final nextDistance = _dragDistance + details.delta.dx;
    _dragDistance = nextDistance > 0 ? nextDistance : 0;
  }

  void _handleDragEnd(DragEndDetails details) {
    final shouldDismiss =
        _dragDistance >= _dismissDistance ||
        (details.primaryVelocity ?? 0) >= _dismissVelocity;
    _dragDistance = 0;
    if (shouldDismiss) widget.onDismiss();
  }

  void _handleDragCancel() {
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('compact-chat-edge-swipe'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      child: const SizedBox.expand(),
    );
  }
}

class _RoomList extends StatelessWidget {
  const _RoomList({
    required this.store,
    this.onRoomFavouriteChanged,
    this.onRoomTap,
    this.query = '',
    this.roomListLoading = false,
    this.onCreateRoom,
    super.key,
  });

  final RoomListStateStore store;
  final RoomFavouriteChange? onRoomFavouriteChanged;
  final ValueChanged<String>? onRoomTap;
  final String query;
  final bool roomListLoading;
  final VoidCallback? onCreateRoom;

  Future<void> _showRoomOptionsSheet(
    BuildContext context,
    String roomId,
  ) async {
    await _adaptiveSurface<void>(
      context,
      (sheetContext) => SafeArea(
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
                    onTap: () async {
                      final nextFavourite = !favourite;
                      store.setFavourite(roomId, nextFavourite);
                      final persist = onRoomFavouriteChanged;
                      if (persist == null) return;
                      try {
                        await persist(roomId, nextFavourite);
                      } catch (_) {
                        store.setFavourite(roomId, favourite);
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Could not update favourite.'),
                            ),
                          );
                      }
                    },
                  );
                },
              ),
              const Divider(height: KiteSpacing.lg),
              ListTile(
                key: Key('room-hide-$roomId'),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 52,
                leading: Icon(
                  Icons.visibility_off_outlined,
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
                title: const Text('Hide chat on this device'),
                subtitle: const Text(
                  'This does not leave or change the Matrix room.',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  store.hideRoom(roomId);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Chat hidden on this device.'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => store.showRoom(roomId),
                        ),
                      ),
                    );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomOptionsMenu(
    BuildContext context,
    String roomId,
    Offset position,
  ) async {
    if (!_isDesktopPlatform(context)) {
      await _showRoomOptionsSheet(context, roomId);
      return;
    }
    final favourite = store.roomSignal(roomId).peek().isFavourite;
    final action = await showMenu<String>(
      context: context,
      position: _popupPosition(context, position),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'favourite',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              favourite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            title: Text(
              favourite ? 'Remove from favourites' : 'Add to favourites',
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'hide',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Hide chat on this device'),
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == 'hide') {
      store.hideRoom(roomId);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Chat hidden on this device.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => store.showRoom(roomId),
            ),
          ),
        );
      return;
    }
    final nextFavourite = !favourite;
    store.setFavourite(roomId, nextFavourite);
    final persist = onRoomFavouriteChanged;
    if (persist == null) return;
    try {
      await persist(roomId, nextFavourite);
    } catch (_) {
      store.setFavourite(roomId, favourite);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not update favourite.')),
        );
    }
  }

  Widget _roomRow(BuildContext context, String roomId, double rowExtent) {
    return SizedBox(
      height: rowExtent,
      child: SignalBuilder(
        builder: (context) {
          final room = store.roomSignal(roomId).value;
          final unreadThreadCount = threadController
              .unreadThreadCountForRoom(room.id)
              .value;
          return _RoomListRow(
            key: ValueKey<String>(room.id),
            room: room,
            unreadThreadCount: unreadThreadCount,
            onLongPress: () => _showRoomOptionsSheet(context, room.id),
            onSecondaryTapDown: (details) =>
                _showRoomOptionsMenu(context, room.id, details.globalPosition),
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
          final normalizedQuery = query.trim().toLowerCase();
          final ids = store.visibleRoomIds.value
              .where((roomId) {
                if (normalizedQuery.isEmpty) return true;
                final room = store.roomSignal(roomId).value;
                return room.name.toLowerCase().contains(normalizedQuery) ||
                    room.latestEventBody.toLowerCase().contains(
                      normalizedQuery,
                    ) ||
                    (room.latestSender?.toLowerCase().contains(
                          normalizedQuery,
                        ) ??
                        false);
              })
              .toList(growable: false);
          final showCreateRoom =
              normalizedQuery.isNotEmpty && onCreateRoom != null;
          if (ids.isEmpty && !showCreateRoom) {
            if (roomListLoading && store.roomIds.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(key: Key('room-list-loading')),
              );
            }
            return Center(
              child: Text(
                normalizedQuery.isEmpty &&
                        store.selectedFilter.value != RoomListFilter.all
                    ? 'No chats match this filter'
                    : 'No chats found',
              ),
            );
          }
          return ListView.builder(
            key: const Key('room-list'),
            itemCount: ids.length + (showCreateRoom ? 1 : 0),
            itemExtent: rowExtent,
            itemBuilder: (context, index) {
              if (showCreateRoom && index == 0) {
                return SizedBox(
                  height: rowExtent,
                  child: ListTile(
                    key: const Key('create-room-search-result'),
                    leading: const Icon(Icons.add_box_outlined),
                    title: const Text('Create room'),
                    subtitle: const Text('Private or public room'),
                    onTap: onCreateRoom,
                  ),
                );
              }
              final roomIndex = showCreateRoom ? index - 1 : index;
              return _roomRow(context, ids[roomIndex], rowExtent);
            },
          );
        },
      ),
    );
  }
}

class _RoomListRow extends StatefulWidget {
  const _RoomListRow({
    super.key,
    required this.room,
    required this.unreadThreadCount,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  final RoomListEntry room;
  final int unreadThreadCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

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
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: ListTile(
            key: Key('room-${room.id}'),
            focusNode: _focusNode,
            focusColor: Colors.transparent,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiteSpacing.md,
            ),
            leading: Builder(
              builder: (context) {
                final avatarUri = Uri.tryParse(room.avatarUrl ?? '');
                final avatarImage =
                    avatarUri != null && avatarUri.scheme == 'mxc'
                    ? _homeAvatarImageProvider(context)?.call(avatarUri)
                    : null;
                return _AvatarCircle(
                  radius: 22,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurface,
                  image: avatarImage,
                  fallback: Text(
                    room.name.characters.first,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
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
                        fontWeight: room.unreadCount > 0
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
            trailing:
                room.hasMention ||
                    room.hasMutedActivity ||
                    room.unreadCount > 0 ||
                    unreadThreadCount > 0
                ? _RoomIndicators(
                    room: room,
                    unreadThreadCount: unreadThreadCount,
                  )
                : null,
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
  replyInThread,
  edit,
  copy,
  share,
  forward,
  report,
  redact,
  endPoll,
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
  const _ChatPanel({
    this.showHeader = true,
    this.roomListStore,
    this.roomManagement,
    this.memberManagement,
    this.calls,
    this.onTimelineHistoryRequested,
    this.timelineReloading = false,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final bool showHeader;
  final RoomListStateStore? roomListStore;
  final RoomManagementCoordinator? roomManagement;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final KiteCallCoordinator? calls;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final bool timelineReloading;
  final RoomMembersLoader? roomMembersLoader;
  final bool memberModerationEnabled;

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
          _ChatHeader(
            roomListStore: widget.roomListStore,
            roomManagement: widget.roomManagement,
            memberManagement: widget.memberManagement,
            calls: widget.calls,
            roomMembersLoader: widget.roomMembersLoader,
            memberModerationEnabled: widget.memberModerationEnabled,
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: _Timeline(
            onReply: _reply,
            onEdit: _edit,
            onTimelineHistoryRequested: widget.onTimelineHistoryRequested,
            timelineReloading: widget.timelineReloading,
          ),
        ),
        const _TypingIndicator(),
        const Divider(height: 1),
        SafeArea(top: false, child: _Composer(key: _composerKey)),
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
              final users = _homeTimelineController(context)
                  .typingUsersFor(roomId)
                  .value;
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
  const _ChatHeader({
    this.roomListStore,
    this.roomManagement,
    this.memberManagement,
    this.calls,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final RoomListStateStore? roomListStore;
  final RoomManagementCoordinator? roomManagement;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final KiteCallCoordinator? calls;
  final RoomMembersLoader? roomMembersLoader;
  final bool memberModerationEnabled;

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
            final store = roomListStore;
            final room = store == null
                ? RoomListEntry.fromBenchmark(BenchmarkFixture.room(roomId))
                : store.roomIds.contains(roomId)
                ? store.roomSignal(roomId).value
                : null;
            if (room == null) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Text('Select a room'),
              );
            }
            final avatarUri = Uri.tryParse(room.avatarUrl ?? '');
            final avatarImage = avatarUri != null && avatarUri.scheme == 'mxc'
                ? _homeAvatarImageProvider(context)?.call(avatarUri)
                : null;
            return Row(
              children: <Widget>[
                _AvatarCircle(
                  radius: 18,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  image: avatarImage,
                  fallback: Text(room.name.characters.first),
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
                    final historyRequest =
                        _HomeTimelineControllerScope.timelineHistoryRequestOf(
                          context,
                        );
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomContentGallery(
                          roomId: roomId,
                          messages: _homeTimelineController(context)
                              .messagesFor(roomId),
                          onLoadOlder: historyRequest == null
                              ? null
                              : () => historyRequest(roomId, 0),
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
                          management: roomManagement,
                          memberManagement: memberManagement,
                          calls: calls,
                          isDirect: room.isDirect,
                          membersLoader: roomMembersLoader,
                          memberModerationEnabled: memberModerationEnabled,
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
  const _Timeline({
    required this.onReply,
    required this.onEdit,
    this.onTimelineHistoryRequested,
    this.timelineReloading = false,
  });

  final _ComposerAction onReply;
  final _ComposerAction onEdit;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final bool timelineReloading;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentTimelineSliverKey = GlobalKey();
  final GlobalKey _unreadMarkerKey = GlobalKey();
  final GlobalKey _focusedMessageKey = GlobalKey();
  String? _displayedRoomId;
  String? _focusedMessageId;
  String? _historyBoundaryMessageId;
  List<TimelineMessage> _displayedMessages = const <TimelineMessage>[];
  List<TimelineMessage>? _pendingTailMessages;
  String? _lastHistoryRequestKey;
  bool _historyProbeScheduled = false;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    _flushPendingAtTail();
    final roomId = _displayedRoomId;
    if (!mounted || roomId == null) return;
    _requestHistoryIfNearOldest(roomId, _displayedMessages.length);
  }

  void _flushPendingAtTail() {
    final pending = _pendingTailMessages;
    if (!mounted || pending == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.minScrollExtent + 0.5) return;
    setState(() {
      _displayedMessages = pending;
      _pendingTailMessages = null;
    });
  }

  void _scheduleHistoryProbe(String roomId, int messageCount) {
    if (widget.timelineReloading ||
        _historyProbeScheduled ||
        widget.onTimelineHistoryRequested == null) {
      return;
    }
    _historyProbeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyProbeScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      _requestHistoryIfNearOldest(roomId, messageCount);
    });
  }

  void _requestHistoryIfNearOldest(String roomId, int messageCount) {
    if (widget.timelineReloading) return;
    final request = widget.onTimelineHistoryRequested;
    if (request == null || !_scrollController.hasClients) return;
    final requestKey = '$roomId:$messageCount';
    if (_scrollController.position.extentAfter > 520) {
      if (_lastHistoryRequestKey == requestKey) {
        _lastHistoryRequestKey = null;
      }
      return;
    }
    if (_lastHistoryRequestKey == requestKey || _historyLoading) return;
    _lastHistoryRequestKey = requestKey;
    setState(() => _historyLoading = true);
    unawaited(
      request(roomId, 0)
          .catchError((Object _) {
            if (mounted && _lastHistoryRequestKey == requestKey) {
              _lastHistoryRequestKey = null;
            }
          })
          .whenComplete(() {
            if (!mounted) return;
            setState(() => _historyLoading = false);
          }),
    );
  }

  Future<void> _jumpToEvent(String roomId, String eventId) async {
    if (!_scrollController.hasClients) return;
    final messages = _homeTimelineController(context)
        .messagesFor(roomId)
        .peek();
    final targetIndex = messages.indexWhere((message) => message.id == eventId);
    if (targetIndex < 0) return;

    if (_focusedMessageId != eventId) {
      setState(() => _focusedMessageId = eventId);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
    }
    if (!mounted) return;

    final retainedContext = _focusedMessageKey.currentContext;
    final retained = retainedContext?.findRenderObject();
    if (retainedContext != null &&
        retainedContext.mounted &&
        retained != null &&
        retained.attached) {
      await Scrollable.ensureVisible(
        retainedContext,
        alignment: 0.34,
        duration: KiteMotion.resolve(context, KiteMotion.standard),
        curve: KiteMotion.standardCurve,
      );
      return;
    }

    final reverseIndex = messages.length - 1 - targetIndex;
    final denominator = messages.length <= 1 ? 1 : messages.length - 1;
    final position = _scrollController.position;
    final targetOffset = position.maxScrollExtent * reverseIndex / denominator;
    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = (clampedOffset - position.pixels).abs();
    if (distance > position.viewportDimension) {
      position.jumpTo(clampedOffset);
    } else {
      await position.animateTo(
        clampedOffset,
        duration: KiteMotion.resolve(context, KiteMotion.deliberate),
        curve: KiteMotion.standardCurve,
      );
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final targetContext = _focusedMessageKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.34,
        duration: KiteMotion.resolve(context, KiteMotion.standard),
        curve: KiteMotion.standardCurve,
      );
    }
  }

  Future<void> _jumpToUnread(String roomId) async {
    final eventId = _homeTimelineController(context)
        .unreadMarkerFor(roomId)
        .peek();
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

    final messages = _homeTimelineController(context)
        .messagesFor(roomId)
        .peek();
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
        final sourceMessages = _homeTimelineController(context)
            .messagesFor(roomId)
            .value;
        if (_displayedRoomId != roomId) {
          _displayedRoomId = roomId;
          _focusedMessageId = null;
          _displayedMessages = sourceMessages;
          _historyBoundaryMessageId = sourceMessages.isEmpty
              ? null
              : sourceMessages.first.id;
          _pendingTailMessages = null;
        } else if (!_sameMessageIdentityList(
          _displayedMessages,
          sourceMessages,
        )) {
          final preservedHistoryPixels =
              _isMessageHistoryPrepend(_displayedMessages, sourceMessages)
              ? _preservedHistoryPixels()
              : null;
          final awayFromTail =
              _scrollController.hasClients &&
              _scrollController.position.pixels >
                  _scrollController.position.minScrollExtent + 0.5;
          final remoteTailAppend =
              awayFromTail &&
              _isStrictMessageTailAppend(_displayedMessages, sourceMessages) &&
              sourceMessages
                  .skip(_displayedMessages.length)
                  .every((message) => !message.id.startsWith('kite-local-'));
          if (remoteTailAppend) {
            _pendingTailMessages = sourceMessages;
          } else {
            if (preservedHistoryPixels != null &&
                _scrollController.hasClients) {
              _scrollController.position.correctPixels(preservedHistoryPixels);
            }
            _displayedMessages = sourceMessages;
            _pendingTailMessages = null;
          }
        }
        final messages = _displayedMessages;
        final historyMessageCount = _historyMessageCount(messages);
        final centerMessageCount = messages.length - historyMessageCount;
        _scheduleHistoryProbe(roomId, messages.length);
        final unreadMarkerEventId = _homeTimelineController(context)
            .unreadMarkerFor(roomId)
            .value;
        return Stack(
          key: const Key('timeline-stack'),
          children: <Widget>[
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is ScrollEndNotification) {
                  _requestHistoryIfNearOldest(roomId, messages.length);
                }
                return false;
              },
              child: CustomScrollView(
                key: const Key('message-list'),
                controller: _scrollController,
                reverse: true,
                semanticChildCount: messages.length,
                scrollCacheExtent: unreadMarkerEventId == null
                    ? null
                    : const ScrollCacheExtent.viewport(1.8),
                slivers: <Widget>[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: KiteSpacing.sm),
                  ),
                  SliverList.builder(
                    key: _currentTimelineSliverKey,
                    itemCount: centerMessageCount,
                    addSemanticIndexes: false,
                    findChildIndexCallback: (key) => _messageChildIndexForKey(
                      messages,
                      key,
                      startIndex: historyMessageCount,
                      endIndex: messages.length,
                    ),
                    itemBuilder: (context, index) {
                      final sourceIndex = messages.length - 1 - index;
                      return _buildMessageRow(
                        roomId: roomId,
                        message: messages[sourceIndex],
                        previousMessage: sourceIndex > 0
                            ? messages[sourceIndex - 1]
                            : null,
                        semanticsOrder: sourceIndex.toDouble(),
                        unreadMarkerEventId: unreadMarkerEventId,
                      );
                    },
                  ),
                  SliverList.builder(
                    itemCount: historyMessageCount,
                    addSemanticIndexes: false,
                    findChildIndexCallback: (key) => _messageChildIndexForKey(
                      messages,
                      key,
                      startIndex: 0,
                      endIndex: historyMessageCount,
                    ),
                    itemBuilder: (context, index) {
                      final sourceIndex = historyMessageCount - 1 - index;
                      return _buildMessageRow(
                        roomId: roomId,
                        message: messages[sourceIndex],
                        previousMessage: sourceIndex > 0
                            ? messages[sourceIndex - 1]
                            : null,
                        semanticsOrder: sourceIndex.toDouble(),
                        unreadMarkerEventId: unreadMarkerEventId,
                      );
                    },
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: KiteSpacing.sm),
                  ),
                ],
              ),
            ),
            if (widget.timelineReloading || _historyLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Semantics(
                  liveRegion: true,
                  label: widget.timelineReloading
                      ? 'Loading recent messages'
                      : 'Loading more messages',
                  child: const _IndeterminateHistoryBar(
                    key: Key('timeline-history-loading'),
                  ),
                ),
              ),
            if (messages.isEmpty &&
                (widget.timelineReloading || _historyLoading))
              Center(
                child: Text(
                  widget.timelineReloading
                      ? 'Loading recent messages…'
                      : 'Loading messages…',
                  key: const Key('timeline-history-loading-label'),
                  style: KiteTypography.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Positioned(
              right: KiteSpacing.md,
              bottom: KiteSpacing.md,
              child: SignalBuilder(
                builder: (context) {
                  final eventId = _homeTimelineController(context)
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

  double? _preservedHistoryPixels() {
    if (!_scrollController.hasClients) return null;
    final renderObject = _currentTimelineSliverKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderSliver) return null;
    final position = _scrollController.position;
    final mappedPixels =
        renderObject.constraints.scrollOffset +
        renderObject.constraints.precedingScrollExtent;
    return mappedPixels < position.pixels ? mappedPixels : position.pixels;
  }

  int _historyMessageCount(List<TimelineMessage> messages) {
    if (messages.isEmpty) {
      _historyBoundaryMessageId = null;
      return 0;
    }
    final boundaryMessageId = _historyBoundaryMessageId;
    if (boundaryMessageId == null) {
      _historyBoundaryMessageId = messages.first.id;
      return 0;
    }
    final boundaryIndex = messages.indexWhere(
      (message) => message.id == boundaryMessageId,
    );
    if (boundaryIndex >= 0) return boundaryIndex;
    _historyBoundaryMessageId = messages.first.id;
    return 0;
  }

  Widget _buildMessageRow({
    required String roomId,
    required TimelineMessage message,
    required TimelineMessage? previousMessage,
    required double semanticsOrder,
    required String? unreadMarkerEventId,
  }) {
    final messageKey = ValueKey<String>(message.id);
    final isUnreadMarker = message.id == unreadMarkerEventId;
    final showDateSeparator = _startsNewTimelineDay(previousMessage, message);
    final isFocused = message.id == _focusedMessageId;
    final row = _MessageRow(
      key: isUnreadMarker || showDateSeparator ? null : messageKey,
      roomId: roomId,
      message: message,
      semanticsOrder: semanticsOrder,
      onReply: widget.onReply,
      onEdit: widget.onEdit,
      onJumpToEvent: (eventId) => unawaited(_jumpToEvent(roomId, eventId)),
      focusAnchorKey: isFocused ? _focusedMessageKey : null,
      focused: isFocused,
    );
    final messageRow = isUnreadMarker
        ? _UnreadMarkerOverlay(
            key: showDateSeparator ? null : messageKey,
            markerKey: _unreadMarkerKey,
            child: row,
          )
        : row;
    if (!showDateSeparator) return messageRow;
    return KeyedSubtree(
      key: messageKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TimelineDateSeparator(eventId: message.id, date: message.sentAt!),
          messageRow,
        ],
      ),
    );
  }
}

String _timelineTimestampLabel(BuildContext context, TimelineMessage message) {
  if (message.id.startsWith('kite-local-')) return message.timeLabel;
  final sentAt = message.sentAt;
  if (sentAt == null) return message.timeLabel;
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(sentAt),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

bool _startsNewTimelineDay(
  TimelineMessage? previousMessage,
  TimelineMessage message,
) {
  final current = message.sentAt;
  if (current == null) return false;
  if (previousMessage == null) return true;
  final previous = previousMessage.sentAt;
  if (previous == null) return false;
  return previous.year != current.year ||
      previous.month != current.month ||
      previous.day != current.day;
}

class _TimelineDateSeparator extends StatelessWidget {
  const _TimelineDateSeparator({required this.eventId, required this.date});

  final String eventId;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = MaterialLocalizations.of(context).formatMediumDate(date);
    return Semantics(
      header: true,
      label: label,
      child: Padding(
        key: Key('date-separator-$eventId'),
        padding: const EdgeInsets.symmetric(
          horizontal: KiteSpacing.md,
          vertical: KiteSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: Divider(color: colors.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
              child: Text(
                label,
                style: KiteTypography.metadata.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.outlineVariant)),
          ],
        ),
      ),
    );
  }
}

class _IndeterminateHistoryBar extends StatelessWidget {
  const _IndeterminateHistoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceContainerHighest),
        child: Align(
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 0.34,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(KiteRadii.sm),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int? _messageChildIndexForKey(
  List<TimelineMessage> messages,
  Key key, {
  required int startIndex,
  required int endIndex,
}) {
  if (key is! ValueKey<String>) return null;
  for (var index = startIndex; index < endIndex; index++) {
    if (messages[index].id == key.value) {
      return endIndex - 1 - index;
    }
  }
  return null;
}

bool _isMessageHistoryPrepend(
  List<TimelineMessage> previous,
  List<TimelineMessage> next,
) {
  if (previous.isEmpty || next.length <= previous.length) return false;
  final offset = next.length - previous.length;
  if (offset <= 0) return false;
  for (var index = 0; index < previous.length; index++) {
    if (previous[index].id != next[index + offset].id) return false;
  }
  return true;
}

bool _sameMessageIdentityList(
  List<TimelineMessage> left,
  List<TimelineMessage> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}

bool _isStrictMessageTailAppend(
  List<TimelineMessage> previous,
  List<TimelineMessage> next,
) {
  if (previous.isEmpty || next.length <= previous.length) return false;
  for (var index = 0; index < previous.length; index++) {
    if (!identical(previous[index], next[index])) return false;
  }
  return true;
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
  const _UnreadMarkerOverlay({
    super.key,
    required this.markerKey,
    required this.child,
  });

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
    required this.onJumpToEvent,
    this.focusAnchorKey,
    this.focused = false,
  });

  final String roomId;
  final TimelineMessage message;
  final double semanticsOrder;
  final _ComposerAction onReply;
  final _ComposerAction onEdit;
  final ValueChanged<String> onJumpToEvent;
  final Key? focusAnchorKey;
  final bool focused;

  void _openMedia(BuildContext context) {
    final model = TimelineMediaViewerModel.fromMessages(
      roomId: roomId,
      messages: _homeTimelineController(context).messagesFor(roomId).peek(),
      initialMessageId: message.id,
      imageProvider: _homeTimelineMediaImageProvider(context),
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

  Future<void> _showEditHistory(BuildContext context) async {
    await _adaptiveSurface<void>(
      context,
      (_) => _EditHistorySheet(message: message),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await _adaptiveSurface<_MessageAction>(
      context,
      (surfaceContext) => _MessageActionSheet(
        message: message,
        onReact: (emoji) {
          _homeTimelineController(context).toggleReaction(message, emoji);
          Navigator.of(surfaceContext).pop();
        },
      ),
      scroll: true,
    );
    if (!context.mounted || action == null) return;
    await _performMessageAction(context, action);
  }

  Future<void> _performMessageAction(
    BuildContext context,
    _MessageAction action,
  ) async {
    switch (action) {
      case _MessageAction.reply:
        onReply(roomId, message);
      case _MessageAction.replyInThread:
        await Navigator.of(context).push(
          ThreadRoute(
            roomId: roomId,
            parent: message,
            reduceMotion: KiteMotion.prefersReducedMotion(context),
          ),
        );
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
        await _homeTimelineController(context).shareMessage(roomId, message);
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
        final destinations = await _adaptiveSurface<List<String>>(
          context,
          (_) => _ForwardMessageSheet(
            currentRoomId: roomId,
            message: message,
            rooms: _forwardDestinationRooms(context),
          ),
          scroll: true,
        );
        if (!context.mounted || destinations == null || destinations.isEmpty) {
          return;
        }
        final forwarded = _homeTimelineController(context)
            .forwardText(message, destinations);
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
        final reason = await _adaptiveSurface<String>(
          context,
          (_) => _ReportMessageSheet(message: message),
        );
        if (!context.mounted || reason == null) return;
        try {
          await _homeTimelineController(context)
              .reportMessage(roomId, message, reason);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Could not send report. Try again.'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          return;
        }
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
      case _MessageAction.endPoll:
        await _homeTimelineController(context).endPoll(roomId, message);
      case _MessageAction.reactionPicker:
        final emoji = await _adaptiveSurface<String>(
          context,
          (_) => const _ReactionPickerSheet(),
        );
        if (!context.mounted || emoji == null) return;
        _homeTimelineController(context).toggleReaction(message, emoji);
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
          final redacted = await _homeTimelineController(context)
              .redactText(roomId, message);
          if (!redacted && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Could not remove message. Try again.'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
          }
        }
    }
  }

  Future<void> _showDesktopActions(
    BuildContext context,
    Offset position,
  ) async {
    if (message.redacted) return;
    final entries =
        <
          ({
            _MessageAction action,
            IconData icon,
            String label,
            bool destructive,
          })
        >[
          (
            action: _MessageAction.reply,
            icon: Icons.reply_rounded,
            label: AppLocalizations.of(context).replyAction,
            destructive: false,
          ),
          (
            action: _MessageAction.replyInThread,
            icon: Icons.forum_outlined,
            label: 'Reply in thread',
            destructive: false,
          ),
          (
            action: _MessageAction.reactionPicker,
            icon: Icons.add_reaction_outlined,
            label: 'React',
            destructive: false,
          ),
          if (message.body.isNotEmpty)
            (
              action: _MessageAction.copy,
              icon: Icons.content_copy_rounded,
              label: message.attachment == null
                  ? AppLocalizations.of(context).copyTextAction
                  : 'Copy caption',
              destructive: false,
            ),
          if (message.poll == null)
            (
              action: _MessageAction.share,
              icon: Icons.share_outlined,
              label: 'Share',
              destructive: false,
            ),
          if (message.poll == null)
            (
              action: _MessageAction.forward,
              icon: Icons.forward_to_inbox_rounded,
              label: 'Forward',
              destructive: false,
            ),
          if (!message.mine)
            (
              action: _MessageAction.report,
              icon: Icons.flag_outlined,
              label: 'Report',
              destructive: false,
            ),
          if (message.mine && message.poll == null)
            (
              action: _MessageAction.edit,
              icon: Icons.edit_outlined,
              label: AppLocalizations.of(context).editMessageAction,
              destructive: false,
            ),
          if (message.mine &&
              message.poll != null &&
              !message.poll!.isEnded &&
              !message.poll!.isEnding)
            (
              action: _MessageAction.endPoll,
              icon: Icons.stop_circle_outlined,
              label: 'End poll',
              destructive: false,
            ),
          if (message.mine)
            (
              action: _MessageAction.redact,
              icon: Icons.delete_outline_rounded,
              label: AppLocalizations.of(context).deleteMessageAction,
              destructive: true,
            ),
        ];
    final action = await showMenu<_MessageAction>(
      context: context,
      position: _popupPosition(context, position),
      items: <PopupMenuEntry<_MessageAction>>[
        for (final entry in entries)
          PopupMenuItem<_MessageAction>(
            value: entry.action,
            child: Row(
              children: <Widget>[
                Icon(
                  entry.icon,
                  size: 19,
                  color: entry.destructive
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: KiteSpacing.sm),
                Text(
                  entry.label,
                  style: entry.destructive
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    await _performMessageAction(context, action);
  }

  Future<void> _performAccessibleAction(
    BuildContext context,
    _MessageAction action,
  ) async {
    switch (action) {
      case _MessageAction.reply:
        onReply(roomId, message);
      case _MessageAction.replyInThread:
        await Navigator.of(context).push(
          ThreadRoute(
            roomId: roomId,
            parent: message,
            reduceMotion: KiteMotion.prefersReducedMotion(context),
          ),
        );
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
      case _MessageAction.endPoll:
        await _homeTimelineController(context).endPoll(roomId, message);
      case _MessageAction.share:
        await _homeTimelineController(context).shareMessage(roomId, message);
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
          final redacted = await _homeTimelineController(context)
              .redactText(roomId, message);
          if (!redacted && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Could not remove message. Try again.'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
          }
        }
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
        onSecondaryTapDown: (details) =>
            _showDesktopActions(context, details.globalPosition),
        child: Semantics(
          customSemanticsActions: message.redacted
              ? const <CustomSemanticsAction, VoidCallback>{}
              : <CustomSemanticsAction, VoidCallback>{
                  CustomSemanticsAction(label: localizations.replyAction): () =>
                      unawaited(
                        _performAccessibleAction(context, _MessageAction.reply),
                      ),
                  const CustomSemanticsAction(label: 'Reply in thread'): () =>
                      unawaited(
                        _performAccessibleAction(
                          context,
                          _MessageAction.replyInThread,
                        ),
                      ),
                  if (message.body.isNotEmpty)
                    CustomSemanticsAction(
                      label: localizations.copyTextAction,
                    ): () => unawaited(
                      _performAccessibleAction(context, _MessageAction.copy),
                    ),
                  if (message.poll == null)
                    const CustomSemanticsAction(label: 'Share'): () =>
                        unawaited(
                          _performAccessibleAction(
                            context,
                            _MessageAction.share,
                          ),
                        ),
                  if (message.mine && message.poll == null)
                    CustomSemanticsAction(
                      label: localizations.editMessageAction,
                    ): () => unawaited(
                      _performAccessibleAction(context, _MessageAction.edit),
                    ),
                  if (message.mine &&
                      message.poll != null &&
                      !message.poll!.isEnded &&
                      !message.poll!.isEnding)
                    const CustomSemanticsAction(label: 'End poll'): () =>
                        unawaited(
                          _performAccessibleAction(
                            context,
                            _MessageAction.endPoll,
                          ),
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
                    _MessageReplyPreview(
                      message: message,
                      onTap: message.replyToMessageId == null
                          ? null
                          : () => onJumpToEvent(message.replyToMessageId!),
                    ),
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
                      final location = message.location;
                      final poll = message.poll;
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
                              audioPlaybackState: message.audioPlaybackState,
                              imageProvider:
                                  _homeTimelineMediaImageProvider(context)
                                      ?.call(
                                        attachment,
                                        TimelineMediaImageVariant.thumbnail,
                                      ),
                              heroTag: attachment.kind.isVisualMedia
                                  ? timelineMediaHeroTag(message)
                                  : null,
                              onTap: attachment.kind.isVisualMedia
                                  ? () => _openMedia(context)
                                  : null,
                              onToggleAudio: attachment.kind.isAudio
                                  ? () =>
                                        _homeTimelineController(context)
                                            .toggleAudioPlayback(message)
                                  : null,
                            ),
                          if (attachment != null &&
                              (location != null ||
                                  poll != null ||
                                  message.body.isNotEmpty))
                            const SizedBox(height: KiteSpacing.xs),
                          if (location != null)
                            TimelineLocationCard(
                              messageId: message.id,
                              location: location,
                              onStopLiveLocation:
                                  mine &&
                                      location.kind ==
                                          TimelineLocationKind.liveLocation &&
                                      location.isLiveActive
                                  ? () => unawaited(
                                      _homeTimelineController(context)
                                          .stopLiveLocation(roomId, message),
                                    )
                                  : null,
                            ),
                          if (location != null &&
                              (poll != null || message.body.isNotEmpty))
                            const SizedBox(height: KiteSpacing.xs),
                          if (poll != null)
                            TimelinePollCard(
                              messageId: message.id,
                              poll: poll,
                              onVote: (optionId) => unawaited(
                                _homeTimelineController(context)
                                    .votePoll(roomId, message, optionId),
                              ),
                            ),
                          if (poll != null && message.body.isNotEmpty)
                            const SizedBox(height: KiteSpacing.xs),
                          if (message.body.isNotEmpty)
                            TimelineMessageBody(
                              body: message.body,
                              formattedBody: message.formattedBody,
                              textKey: Key('message-body-${message.id}'),
                            ),
                          if (linkPreview != null) ...<Widget>[
                            const SizedBox(height: KiteSpacing.xs),
                            TimelineLinkPreviewCard(
                              key: Key('message-link-preview-${message.id}'),
                              preview: linkPreview,
                              onOpen: () async {
                                await _homeTimelineController(context)
                                    .openLink(linkPreview.uri);
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
                        _timelineTimestampLabel(context, message),
                        key: Key('message-time-${message.id}'),
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
        _ThreadSummaryButton(roomId: roomId, parent: message),
      ],
    );

    final row = Semantics(
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
              _MessageAvatar(
                sender: message.sender,
                avatarUrl: message.senderAvatarUrl,
              ),
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
    if (!focused || focusAnchorKey == null) return row;
    return KeyedSubtree(
      key: focusAnchorKey,
      child: DecoratedBox(
        key: Key('focused-message-${message.id}'),
        decoration: BoxDecoration(
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.72),
            width: KiteStroke.emphasis,
          ),
          borderRadius: BorderRadius.circular(KiteRadii.md),
        ),
        child: row,
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
        return Padding(
          padding: const EdgeInsets.only(top: KiteSpacing.xs),
          child: Semantics(
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
          ),
        );
      },
    );
  }
}

class _MessageReplyPreview extends StatelessWidget {
  const _MessageReplyPreview({required this.message, this.onTap});

  final TimelineMessage message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? null
          : AppLocalizations.of(context).jumpToRepliedMessageLabel,
      child: GestureDetector(
        key: Key('reply-preview-${message.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 132, maxWidth: 460),
          padding: const EdgeInsets.only(left: KiteSpacing.xs),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: colors.primary,
                width: KiteStroke.emphasis,
              ),
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
        ),
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
                  message.poll?.question ?? message.body,
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
                  key: const Key('message-action-reply-thread'),
                  icon: Icons.forum_outlined,
                  label: 'Reply in thread',
                  onTap: () =>
                      Navigator.of(context).pop(_MessageAction.replyInThread),
                ),
                if (message.body.isNotEmpty)
                  _MessageActionButton(
                    key: const Key('message-action-copy'),
                    icon: Icons.content_copy_rounded,
                    label: message.attachment == null
                        ? AppLocalizations.of(context).copyTextAction
                        : 'Copy caption',
                    onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                  ),
                if (message.poll == null)
                  _MessageActionButton(
                    key: const Key('message-action-share'),
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.share),
                  ),
                if (message.poll == null)
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
                if (message.mine && message.poll == null)
                  _MessageActionButton(
                    key: const Key('message-action-edit'),
                    icon: Icons.edit_outlined,
                    label: AppLocalizations.of(context).editMessageAction,
                    onTap: () => Navigator.of(context).pop(_MessageAction.edit),
                  ),
                if (message.mine &&
                    message.poll != null &&
                    !message.poll!.isEnded &&
                    !message.poll!.isEnding)
                  _MessageActionButton(
                    key: const Key('message-action-end-poll'),
                    icon: Icons.stop_circle_outlined,
                    label: 'End poll',
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.endPoll),
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

List<RoomListEntry> _forwardDestinationRooms(BuildContext context) {
  final store = _homeRoomListStore(context);
  if (store == null) {
    return deterministicRoomListEntries(BenchmarkFixture.rooms);
  }
  return List<RoomListEntry>.unmodifiable(<RoomListEntry>[
    for (final roomId in store.roomIds) store.roomSignal(roomId).peek(),
  ]);
}

class _ForwardMessageSheet extends StatefulWidget {
  const _ForwardMessageSheet({
    required this.currentRoomId,
    required this.message,
    required this.rooms,
  });

  final String currentRoomId;
  final TimelineMessage message;
  final List<RoomListEntry> rooms;

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
    final rooms = widget.rooms
        .where((room) => room.id != widget.currentRoomId)
        .where(
          (room) =>
              normalizedQuery.isEmpty ||
              room.name.toLowerCase().contains(normalizedQuery) ||
              room.latestEventBody.toLowerCase().contains(normalizedQuery) ||
              (room.latestSender ?? '').toLowerCase().contains(normalizedQuery),
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
    return Align(
      key: const Key('quick-reaction-row'),
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: KiteSpacing.xs,
        children: <Widget>[
          for (var index = 0; index < reactions.length; index++)
            Semantics(
              button: true,
              label: 'React with ${reactions[index]}',
              child: InkWell(
                key: Key('quick-reaction-$index'),
                onTap: () => onReact(reactions[index]),
                borderRadius: BorderRadius.circular(KiteRadii.pill),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(KiteRadii.pill),
                  ),
                  child: Text(
                    reactions[index],
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
            ),
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
    await _adaptiveSurface<void>(
      context,
      (context) => Padding(
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

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    super.key,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.image,
    required this.fallback,
  });

  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final ImageProvider<Object>? image;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: diameter,
          child: ColoredBox(
            color: backgroundColor,
            child: image == null
                ? Center(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: foregroundColor),
                      child: fallback,
                    ),
                  )
                : Image(
                    image: image!,
                    width: diameter,
                    height: diameter,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: foregroundColor),
                        child: fallback,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({required this.sender, this.avatarUrl});

  final String sender;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatarUri = Uri.tryParse(avatarUrl ?? '');
    final avatarImage = avatarUri != null && avatarUri.scheme == 'mxc'
        ? _homeAvatarImageProvider(context)?.call(avatarUri)
        : null;
    return Semantics(
      image: true,
      label: AppLocalizations.of(context).avatarLabel(sender),
      child: _AvatarCircle(
        radius: 16,
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        image: avatarImage,
        fallback: Text(
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

  Future<void> _showReadReceipts(
    BuildContext context,
    List<String> readers,
  ) async {
    await _adaptiveSurface<void>(
      context,
      (_) => _ReadReceiptDetailsSheet(readers: readers),
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
                onTap: () =>
                    _homeTimelineController(context).retry(roomId, message),
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
    final attachment = await showComposerAttachmentPicker(
      context,
      onLocationSelected: (kind) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            showComposerLocationShareSheet(
              context,
              roomId: roomId,
              kind: kind,
              controller: _homeTimelineController(context),
            ),
          );
        });
      },
      onPollSelected: () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            showComposerPollSheet(
              context,
              roomId: roomId,
              controller: _homeTimelineController(context),
            ),
          );
        });
      },
    );
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
    BuildContext context,
    TextEditingValue value,
  ) {
    final match = _autocompleteMatch(value);
    if (match == null) return const [];
    final candidates = <({String token, String label, IconData icon})>[];
    if (match.prefix == '@') {
      final roomId = selectedRoomId.value;
      final seen = <String>{};
      final messages = _homeTimelineController(context)
          .messagesFor(roomId)
          .value;
      for (final message in messages.reversed) {
        final sender = message.sender.trim();
        if (sender.isEmpty) continue;
        final senderId = message.senderId?.trim();
        final token = senderId != null && senderId.startsWith('@')
            ? senderId
            : '@${sender.replaceAll(RegExp(r'\s+'), '')}';
        if (!seen.add(token)) continue;
        candidates.add((
          token: token,
          label: sender,
          icon: Icons.person_outline_rounded,
        ));
      }
    } else {
      final roomStore = _homeRoomListStore(context);
      final rooms = roomStore == null
          ? deterministicRoomListEntries(BenchmarkFixture.rooms)
          : <RoomListEntry>[
              for (final roomId in roomStore.roomIds)
                roomStore.roomSignal(roomId).value,
            ];
      for (final room in rooms) {
        final label = room.name.trim();
        if (label.isEmpty) continue;
        candidates.add((
          token: '#${label.replaceAll(RegExp(r'\s+'), '-')}',
          label: label,
          icon: Icons.tag_rounded,
        ));
      }
    }
    return candidates
        .where((candidate) {
          final query = match.query;
          if (query.isEmpty) return true;
          return candidate.label.toLowerCase().contains(query) ||
              candidate.token.substring(1).toLowerCase().contains(query);
        })
        .take(6)
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
      _homeTimelineController(context).editText(roomId, contextMessage, body);
      _clearContext(restoreEditDraft: true);
    } else {
      if (body.isEmpty && attachment == null) return;
      if (attachment != null) {
        _homeTimelineController(context).sendAttachment(
          roomId,
          attachment,
          caption: body,
          replyTo: _mode == _ComposerMode.reply ? contextMessage : null,
        );
        _pendingAttachment = null;
        _pendingAttachmentRoomId = null;
      } else {
        _homeTimelineController(context).sendText(
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
    final compactComposer = MediaQuery.sizeOf(context).width < 600;
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
                    final options = _autocompleteOptions(context, value);
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
                  child: !compactComposer && _formattingVisible
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: KiteSpacing.md,
                                vertical: KiteSpacing.xs,
                              ),
                              child: _ComposerFormattingToolbar(
                                onFormat: _applyFormat,
                              ),
                            ),
                          ],
                        )
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
                          KiteSpacing.xxs,
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
                              style: IconButton.styleFrom(
                                minimumSize: const Size.square(48),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                            ),
                            if (!compactComposer)
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
                            if (!compactComposer)
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
                                    minimumSize: const Size.square(48),
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
    return RepaintBoundary(
      child: Material(
        key: const Key('composer-emoji-sheet'),
        elevation: KiteElevation.floating,
        color: context.kiteColors.canvas,
        borderRadius: BorderRadius.circular(KiteRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 60,
          child: ListView.separated(
            key: const Key('composer-emoji-list'),
            padding: const EdgeInsets.symmetric(
              horizontal: KiteSpacing.sm,
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
                    dimension: 44,
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(
                          fontSize: 27,
                          fontFamilyFallback: <String>['Noto Color Emoji'],
                        ),
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
