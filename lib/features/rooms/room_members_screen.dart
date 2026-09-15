import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/features/rooms/room_member_management_controller.dart';
import 'package:signals/signals_flutter.dart';

class RoomMembersScreen extends StatefulWidget {
  const RoomMembersScreen({
    required this.roomId,
    required this.coordinator,
    super.key,
  });

  final String roomId;
  final RoomMemberManagementCoordinator coordinator;

  @override
  State<RoomMembersScreen> createState() => _RoomMembersScreenState();
}

class _RoomMembersScreenState extends State<RoomMembersScreen> {
  late final RoomMemberManagementController _controller;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _controller = RoomMemberManagementController(
      roomId: widget.roomId,
      coordinator: widget.coordinator,
    );
    _searchController = TextEditingController();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _inviteMember() async {
    final userId = await showDialog<String>(
      context: context,
      builder: (_) => const _InviteMemberDialog(),
    );
    if (!mounted || userId == null) return;
    await _controller.invite(userId);
  }

  Future<String?> _requestReportReason({
    required String title,
    required String message,
  }) async {
    var reason = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(message),
            const SizedBox(height: KiteSpacing.md),
            TextField(
              key: const Key('room-report-reason'),
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
              onChanged: (value) => reason = value,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('room-report-submit'),
            onPressed: () => Navigator.of(dialogContext).pop(reason),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _reportRoom() async {
    final reason = await _requestReportReason(
      title: 'Report room?',
      message: 'Send a report to the homeserver moderators for this room.',
    );
    if (!mounted || reason == null) return;
    await _controller.reportRoom(reason: reason);
  }

  Future<void> _leaveRoom() async {
    final confirmed = await _confirmModerationAction(
      context: context,
      title: 'Leave room?',
      message: 'You will stop receiving messages from this room.',
      actionLabel: 'Leave',
    );
    if (!confirmed || !mounted) return;
    await _controller.leaveRoom();
  }

  Future<void> _forgetRoom() async {
    final confirmed = await _confirmModerationAction(
      context: context,
      title: 'Remove local room data?',
      message: 'Remove this left room from Kite on this device.',
      actionLabel: 'Remove data',
    );
    if (!confirmed || !mounted) return;
    await _controller.forgetRoom();
  }

  Future<bool> _confirmModerationAction({
    required BuildContext context,
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('member-moderation-confirm-$actionLabel'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _openMember(RoomMember member) async {
    final powerOptions = _controller.powerOptions(member);
    final moderationOptions = _controller.moderationOptions(member);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KiteSpacing.xl,
              KiteSpacing.xs,
              KiteSpacing.xl,
              KiteSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _MemberAvatar(member: member, radius: 28),
                    const SizedBox(width: KiteSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            member.displayName,
                            key: const Key('member-details-name'),
                            style: KiteTypography.headline,
                          ),
                          const SizedBox(height: KiteSpacing.xxs),
                          Text(
                            member.userId,
                            key: const Key('member-details-user-id'),
                            style: KiteTypography.metadata.copyWith(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KiteSpacing.lg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: sheetContext.kiteColors.field,
                    borderRadius: BorderRadius.circular(KiteRadii.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(KiteSpacing.md),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.admin_panel_settings_outlined),
                        const SizedBox(width: KiteSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _roleLabel(member.powerLevel),
                                key: const Key('member-details-role'),
                                style: KiteTypography.title,
                              ),
                              Text(
                                'Power level ${member.powerLevel}',
                                style: KiteTypography.metadata.copyWith(
                                  color: Theme.of(sheetContext)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KiteSpacing.sm),
                FutureBuilder<RoomMemberPowerOptions>(
                  future: powerOptions,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: KiteSpacing.md),
                        child: Text('Role actions are unavailable right now.'),
                      );
                    }

                    final options = snapshot.requireData;
                    final actions = <Widget>[];
                    void addRoleAction({
                      required int powerLevel,
                      required bool allowed,
                      required String label,
                      required IconData icon,
                    }) {
                      if (!allowed || member.powerLevel == powerLevel) return;
                      actions.add(
                        ListTile(
                          key: Key('member-role-$powerLevel'),
                          minTileHeight: 52,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon),
                          title: Text(label),
                          onTap: () async {
                            final changed = await _controller.setPowerLevel(
                              member,
                              powerLevel,
                            );
                            if (changed && sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                      );
                    }

                    addRoleAction(
                      powerLevel: 0,
                      allowed: options.canSetMember,
                      label: 'Make member',
                      icon: Icons.arrow_downward,
                    );
                    addRoleAction(
                      powerLevel: 50,
                      allowed: options.canSetModerator,
                      label: 'Make moderator',
                      icon: member.powerLevel < 50
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                    );
                    addRoleAction(
                      powerLevel: 100,
                      allowed: options.canSetAdmin,
                      label: 'Make admin',
                      icon: Icons.arrow_upward,
                    );

                    if (actions.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: KiteSpacing.md),
                        child: Text(
                          'You do not have permission to change this member’s role.',
                        ),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    );
                  },
                ),
                ListTile(
                  key: const Key('member-report'),
                  minTileHeight: 52,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report user'),
                  onTap: () async {
                    final reason = await _requestReportReason(
                      title: 'Report ${member.displayName}?',
                      message: 'Send a report about this user to the homeserver moderators.',
                    );
                    if (reason == null) return;
                    final reported = await _controller.reportUser(
                      member,
                      reason: reason,
                    );
                    if (reported && sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
                FutureBuilder<RoomMemberModerationOptions>(
                  future: moderationOptions,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done ||
                        snapshot.hasError ||
                        !snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final options = snapshot.requireData;
                    final actions = <Widget>[];
                    if (options.canKick) {
                      actions.add(
                        ListTile(
                          key: const Key('member-kick'),
                          minTileHeight: 52,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_remove_outlined),
                          title: const Text('Remove from room'),
                          onTap: () async {
                            final confirmed = await _confirmModerationAction(
                              context: sheetContext,
                              title: 'Remove ${member.displayName}?',
                              message: 'They will leave this room but can be invited again.',
                              actionLabel: 'Remove',
                            );
                            if (!confirmed) return;
                            final changed = await _controller.kick(member);
                            if (changed && sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                      );
                    }
                    if (options.canBan) {
                      actions.add(
                        ListTile(
                          key: const Key('member-ban'),
                          minTileHeight: 52,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.block_outlined),
                          title: const Text('Ban from room'),
                          onTap: () async {
                            final confirmed = await _confirmModerationAction(
                              context: sheetContext,
                              title: 'Ban ${member.displayName}?',
                              message: 'They will be removed and cannot rejoin until unbanned.',
                              actionLabel: 'Ban',
                            );
                            if (!confirmed) return;
                            final changed = await _controller.ban(member);
                            if (changed && sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                      );
                    }
                    if (options.canUnban) {
                      actions.add(
                        ListTile(
                          key: const Key('member-unban'),
                          minTileHeight: 52,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.undo_outlined),
                          title: const Text('Unban'),
                          onTap: () async {
                            final confirmed = await _confirmModerationAction(
                              context: sheetContext,
                              title: 'Unban ${member.displayName}?',
                              message: 'They will be allowed to join this room again.',
                              actionLabel: 'Unban',
                            );
                            if (!confirmed) return;
                            final changed = await _controller.unban(member);
                            if (changed && sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                      );
                    }
                    if (actions.isEmpty) return const SizedBox.shrink();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[const Divider(), ...actions],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: <Widget>[
          IconButton(
            key: const Key('member-invite-action'),
            tooltip: 'Invite member',
            onPressed: _inviteMember,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          PopupMenuButton<_RoomSafetyAction>(
            key: const Key('room-safety-actions'),
            tooltip: 'Room actions',
            onSelected: (action) {
              switch (action) {
                case _RoomSafetyAction.report:
                  unawaited(_reportRoom());
                  break;
                case _RoomSafetyAction.leave:
                  unawaited(_leaveRoom());
                  break;
                case _RoomSafetyAction.forget:
                  unawaited(_forgetRoom());
                  break;
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<_RoomSafetyAction>>[
              PopupMenuItem<_RoomSafetyAction>(
                value: _RoomSafetyAction.report,
                child: Text('Report room'),
              ),
              PopupMenuItem<_RoomSafetyAction>(
                value: _RoomSafetyAction.leave,
                child: Text('Leave room'),
              ),
              PopupMenuItem<_RoomSafetyAction>(
                value: _RoomSafetyAction.forget,
                child: Text('Remove local room data'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final members = _controller.members.value;
            final loading = _controller.isLoading.value;
            final errorMessage = _controller.errorMessage.value;

            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.md,
                    KiteSpacing.sm,
                    KiteSpacing.md,
                    KiteSpacing.sm,
                  ),
                  child: TextField(
                    key: const Key('member-search'),
                    controller: _searchController,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search members',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _controller.search,
                  ),
                ),
                SizedBox(
                  height: 4,
                  child: loading
                      ? const LinearProgressIndicator(
                          key: Key('member-search-progress'),
                        )
                      : null,
                ),
                SizedBox(
                  height: 36,
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        errorMessage ?? '',
                        key: const Key('member-error'),
                        textAlign: TextAlign.center,
                        style: KiteTypography.metadata.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: members.isEmpty && !loading
                      ? const _EmptyMembers()
                      : ListView.builder(
                          key: const Key('member-list'),
                          itemCount: members.length,
                          itemExtent: 72,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            return Semantics(
                              button: true,
                              label:
                                  '${member.displayName}, ${_roleLabel(member.powerLevel)}',
                              child: ListTile(
                                key: Key('member-${member.userId}'),
                                minTileHeight: 72,
                                leading: _MemberAvatar(member: member),
                                title: Text(
                                  member.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  member.userId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  _roleLabel(member.powerLevel),
                                  style: KiteTypography.metadata.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                onTap: () => _openMember(member),
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
    );
  }
}

enum _RoomSafetyAction { report, leave, forget }

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog();

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite member'),
      content: TextField(
        key: const Key('member-invite-user-id'),
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Matrix user ID',
          hintText: '@name:server',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('member-invite-submit'),
          onPressed: _submit,
          child: const Text('Invite'),
        ),
      ],
    );
  }
}

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KiteSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.group_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: KiteSpacing.sm),
            const Text('No members found', style: KiteTypography.title),
            const SizedBox(height: KiteSpacing.xs),
            Text(
              'Try another name or Matrix user ID.',
              textAlign: TextAlign.center,
              style: KiteTypography.metadata.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, this.radius = 20});

  final RoomMember member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final display = member.displayName.trim();
    final fallback = member.userId.length > 1 ? member.userId[1] : '?';
    final initial = display.isEmpty ? fallback : display[0];
    return CircleAvatar(radius: radius, child: Text(initial.toUpperCase()));
  }
}

String _roleLabel(int powerLevel) {
  if (powerLevel >= 100) return 'Admin';
  if (powerLevel >= 50) return 'Moderator';
  return 'Member';
}
