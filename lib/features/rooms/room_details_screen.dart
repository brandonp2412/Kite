import 'package:flutter/material.dart';
import 'package:kite/features/rooms/room_members.dart';
import 'package:signals/signals_flutter.dart';

class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({
    required this.roomId,
    required this.roomName,
    this.store,
    super.key,
  });

  final String roomId;
  final String roomName;
  final RoomMembersStore? store;

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
      appBar: AppBar(title: Text(widget.roomName)),
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

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.store, required this.userId});

  final RoomMembersStore store;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final member = store.member(userId);
        final permissions = store.permissions;
        final actor = store.currentUser;
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
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      key: const Key('member-promote'),
                      onPressed: canPromote
                          ? () {
                              store.setRole(userId, nextRole);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Promote'),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('member-demote'),
                      onPressed: canDemote
                          ? () {
                              store.setRole(userId, previousRole);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('Demote'),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('member-kick'),
                      onPressed: canKick
                          ? () {
                              if (store.kick(userId)) {
                                Navigator.of(context).pop();
                              }
                            }
                          : null,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('Kick'),
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
