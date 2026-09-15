import 'package:flutter/material.dart';
import 'package:kite/features/calls/call_launcher.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/features/rooms/room_members_screen.dart';
import 'package:kite/features/rooms/room_settings_screen.dart';
import 'package:signals/signals_flutter.dart';

class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({
    required this.roomId,
    required this.roomName,
    this.store,
    this.management,
    this.memberManagement,
    this.calls,
    this.isDirect = false,
    this.activeGroupCallId,
    this.activeGroupCallKind = KiteCallKind.video,
    super.key,
  });

  final String roomId;
  final String roomName;
  final RoomMembersStore? store;
  final RoomManagementCoordinator? management;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final KiteCallCoordinator? calls;
  final bool isDirect;
  final String? activeGroupCallId;
  final KiteCallKind activeGroupCallKind;

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  late final RoomMembersStore _store;
  late final bool _ownsStore;

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    _store = widget.store ?? RoomMembersFixture.forRoom(widget.roomId);
  }

  @override
  void dispose() {
    if (_ownsStore) _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('room-details-screen'),
      appBar: AppBar(
        title: Text(widget.roomName),
        actions:
            widget.management == null &&
                widget.memberManagement == null &&
                widget.calls == null
            ? null
            : <Widget>[
                if (widget.calls case final calls?)
                  KiteRoomCallLauncher(
                    coordinator: calls,
                    roomId: widget.roomId,
                    roomName: widget.roomName,
                    isDirect: widget.isDirect,
                    activeGroupCallId: widget.activeGroupCallId,
                    activeGroupCallKind: widget.activeGroupCallKind,
                  ),
                if (widget.memberManagement != null)
                  IconButton(
                    key: const Key('room-members-management-button'),
                    tooltip: 'Members and room safety',
                    onPressed: _openManagedMembers,
                    icon: const Icon(Icons.group_outlined),
                  ),
                if (widget.management != null)
                  IconButton(
                    key: const Key('room-settings-button'),
                    tooltip: 'Room settings',
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('member-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search members',
              ),
              onChanged: (value) => _store.query.value = value,
            ),
          ),
          Expanded(
            child: SignalBuilder(
              builder: (context) {
                final members = _store.visibleMembers;
                if (members.isEmpty) {
                  return const Center(
                    key: Key('member-search-empty'),
                    child: Text('No members found'),
                  );
                }
                return ListView.separated(
                  key: const Key('member-list'),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return ListTile(
                      key: Key('member-${member.userId}'),
                      leading: CircleAvatar(
                        child: Text(member.displayName.characters.first),
                      ),
                      title: Text(member.displayName),
                      subtitle: Text(member.userId),
                      trailing: _RolePill(role: member.role),
                      onTap: () => _showMember(member.userId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openManagedMembers() async {
    final management = widget.memberManagement;
    if (management == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            RoomMembersScreen(roomId: widget.roomId, coordinator: management),
      ),
    );
  }

  Future<void> _openSettings() async {
    final management = widget.management;
    if (management == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            RoomSettingsScreen(roomId: widget.roomId, coordinator: management),
      ),
    );
  }

  Future<void> _showMember(String userId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _MemberSheet(store: _store, userId: userId),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final RoomMemberRole role;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(role.label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.store, required this.userId});

  final RoomMembersStore store;
  final String userId;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  bool _confirmingKick = false;
  bool _confirmingBan = false;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final member = widget.store.member(widget.userId);
        final permissions = widget.store.permissions;
        final actor = widget.store.currentUser;
        final nextRole = _nextRole(member.role);
        final previousRole = _previousRole(member.role);
        final canPromote =
            nextRole != null &&
            permissions.canChangeRole(
              actor: actor,
              target: member,
              role: nextRole,
            );
        final canDemote =
            previousRole != null &&
            permissions.canChangeRole(
              actor: actor,
              target: member,
              role: previousRole,
            );
        final canKick = permissions.canKick(actor: actor, target: member);
        final canBan = permissions.canBan(actor: actor, target: member);
        final canUnban = permissions.canUnban(actor: actor, target: member);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              key: const Key('member-profile-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  member.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(member.userId),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    _RolePill(role: member.role),
                    const SizedBox(width: 8),
                    Text('Power ${member.powerLevel}'),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: member.membership == RoomMembership.banned
                      ? <Widget>[
                          FilledButton.tonalIcon(
                            key: const Key('member-unban'),
                            onPressed: canUnban
                                ? () async {
                                    if (await widget.store.unban(
                                          widget.userId,
                                        ) &&
                                        context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.person_add_alt_outlined),
                            label: const Text('Unban'),
                          ),
                        ]
                      : _confirmingKick
                      ? <Widget>[
                          TextButton(
                            key: const Key('member-kick-cancel'),
                            onPressed: () =>
                                setState(() => _confirmingKick = false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            key: const Key('member-kick-confirm'),
                            onPressed: () async {
                              if (await widget.store.kick(widget.userId) &&
                                  context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(Icons.person_remove_outlined),
                            label: Text('Remove ${member.displayName}'),
                          ),
                        ]
                      : _confirmingBan
                      ? <Widget>[
                          TextButton(
                            key: const Key('member-ban-cancel'),
                            onPressed: () =>
                                setState(() => _confirmingBan = false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            key: const Key('member-ban-confirm'),
                            onPressed: () async {
                              if (await widget.store.ban(widget.userId) &&
                                  context.mounted) {
                                setState(() => _confirmingBan = false);
                              }
                            },
                            icon: const Icon(Icons.block_outlined),
                            label: Text('Ban ${member.displayName}'),
                          ),
                        ]
                      : <Widget>[
                          FilledButton.tonalIcon(
                            key: const Key('member-promote'),
                            onPressed: canPromote
                                ? () async {
                                    await widget.store.setRole(
                                      widget.userId,
                                      nextRole,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_upward),
                            label: const Text('Promote'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('member-demote'),
                            onPressed: canDemote
                                ? () async {
                                    await widget.store.setRole(
                                      widget.userId,
                                      previousRole,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Demote'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('member-kick'),
                            onPressed: canKick
                                ? () => setState(() => _confirmingKick = true)
                                : null,
                            icon: const Icon(Icons.person_remove_outlined),
                            label: const Text('Kick'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('member-ban'),
                            onPressed: canBan
                                ? () => setState(() => _confirmingBan = true)
                                : null,
                            icon: const Icon(Icons.block_outlined),
                            label: const Text('Ban'),
                          ),
                        ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

RoomMemberRole? _nextRole(RoomMemberRole role) {
  return switch (role) {
    RoomMemberRole.member => RoomMemberRole.moderator,
    RoomMemberRole.moderator => RoomMemberRole.administrator,
    RoomMemberRole.administrator => null,
  };
}

RoomMemberRole? _previousRole(RoomMemberRole role) {
  return switch (role) {
    RoomMemberRole.administrator => RoomMemberRole.moderator,
    RoomMemberRole.moderator => RoomMemberRole.member,
    RoomMemberRole.member => null,
  };
}
