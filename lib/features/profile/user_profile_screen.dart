import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:signals/signals_flutter.dart';

typedef AvatarPicker = Future<Uri?> Function();
typedef AvatarImageProvider = ImageProvider<Object>? Function(Uri? avatarUri);

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen.own({
    required this.controller,
    this.pickAvatar,
    this.avatarImageProvider,
    this.loadOnInit = true,
    super.key,
  }) : userId = null,
       onOpenRoom = null;

  const UserProfileScreen.user({
    required this.controller,
    required String this.userId,
    this.onOpenRoom,
    this.avatarImageProvider,
    this.loadOnInit = true,
    super.key,
  }) : pickAvatar = null;

  final UserProfileController controller;
  final String? userId;
  final ValueChanged<String>? onOpenRoom;
  final AvatarPicker? pickAvatar;
  final AvatarImageProvider? avatarImageProvider;
  final bool loadOnInit;

  bool get isOwnProfile => userId == null;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.loadOnInit) return;
    if (widget.isOwnProfile) {
      unawaited(widget.controller.loadOwnProfile());
    } else {
      unawaited(widget.controller.loadUserProfile(widget.userId!));
    }
  }

  Future<void> _editDisplayName(MatrixUserProfile profile) async {
    final textController = TextEditingController(
      text: profile.displayName ?? '',
    );
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          key: const Key('profile-display-name-field'),
          controller: textController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Display name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('profile-save-display-name'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final next = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    textController.dispose();
    if (next != null && mounted) {
      await widget.controller.updateDisplayName(next);
    }
  }

  Future<void> _changeAvatar() async {
    final picker = widget.pickAvatar;
    if (picker == null) return;
    final selected = await picker();
    if (selected == null || !mounted) return;
    await widget.controller.updateAvatar(selected);
  }

  Future<void> _openDirectMessage(MatrixUserProfile profile) async {
    final roomId = await widget.controller.openDirectMessage(profile.userId);
    if (roomId != null && mounted) {
      widget.onOpenRoom?.call(roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwnProfile ? 'Your profile' : 'Profile'),
      ),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final profile = widget.isOwnProfile
                ? widget.controller.ownProfile.value
                : widget.controller.viewedProfile.value;
            final loading = widget.controller.isLoading.value;
            final saving = widget.controller.isSaving.value;
            final error = widget.controller.errorMessage.value;
            final busy = loading || saving;

            return ListView(
              key: const Key('user-profile-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('profile-loading-slot'),
                  height: 4,
                  child: loading ? const LinearProgressIndicator() : null,
                ),
                if (profile == null)
                  SizedBox(
                    key: const Key('profile-empty-state'),
                    height: 260,
                    child: Center(
                      child: Text(
                        loading ? 'Loading profile…' : 'Profile unavailable',
                        style: KiteTypography.body,
                      ),
                    ),
                  )
                else ...<Widget>[
                  _ProfileHeader(
                    profile: profile,
                    imageProvider: widget.avatarImageProvider?.call(
                      profile.avatarUri,
                    ),
                  ),
                  if (widget.isOwnProfile)
                    _OwnProfileActions(
                      profile: profile,
                      busy: busy,
                      canChangeAvatar: widget.pickAvatar != null,
                      onEditDisplayName: () => _editDisplayName(profile),
                      onChangeAvatar: _changeAvatar,
                      onRemoveAvatar: profile.avatarUri == null
                          ? null
                          : () => widget.controller.updateAvatar(null),
                    )
                  else
                    _OtherProfileActions(
                      profile: profile,
                      busy: busy,
                      ignored: widget.controller.isIgnored(profile.userId),
                      blocked: widget.controller.isBlocked(profile.userId),
                      onMessage: () => _openDirectMessage(profile),
                      onIgnoredChanged: (value) =>
                          widget.controller.setIgnored(profile.userId, value),
                      onBlockedChanged: (value) =>
                          widget.controller.setBlocked(profile.userId, value),
                    ),
                ],
                SizedBox(
                  key: const Key('profile-status-slot'),
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KiteSpacing.md,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error ?? '',
                          key: const Key('profile-error'),
                          style: KiteTypography.metadata.copyWith(
                            color: error == null
                                ? null
                                : Theme.of(context).colorScheme.error,
                          ),
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
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.imageProvider});

  final MatrixUserProfile profile;
  final ImageProvider<Object>? imageProvider;

  @override
  Widget build(BuildContext context) {
    final label = _profileLabel(profile);
    return SizedBox(
      key: const Key('profile-header'),
      height: 220,
      child: Padding(
        padding: const EdgeInsets.all(KiteSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Semantics(
              image: true,
              label: '$label avatar',
              child: CircleAvatar(
                key: const Key('profile-avatar'),
                radius: 48,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Text(
                        _profileInitial(profile),
                        style: Theme.of(context).textTheme.headlineMedium,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: KiteSpacing.md),
            Text(
              label,
              key: const Key('profile-display-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: KiteSpacing.xs),
            Text(
              profile.userId,
              key: const Key('profile-user-id'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

class _OwnProfileActions extends StatelessWidget {
  const _OwnProfileActions({
    required this.profile,
    required this.busy,
    required this.canChangeAvatar,
    required this.onEditDisplayName,
    required this.onChangeAvatar,
    required this.onRemoveAvatar,
  });

  final MatrixUserProfile profile;
  final bool busy;
  final bool canChangeAvatar;
  final VoidCallback onEditDisplayName;
  final VoidCallback onChangeAvatar;
  final VoidCallback? onRemoveAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          key: const Key('edit-display-name'),
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Display name'),
          subtitle: Text(profile.displayName ?? profile.userId),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: !busy,
          onTap: busy ? null : onEditDisplayName,
        ),
        if (canChangeAvatar)
          ListTile(
            key: const Key('change-profile-avatar'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Change avatar'),
            enabled: !busy,
            onTap: busy ? null : onChangeAvatar,
          ),
        if (profile.avatarUri != null)
          ListTile(
            key: const Key('remove-profile-avatar'),
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Remove avatar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: !busy,
            onTap: busy ? null : onRemoveAvatar,
          ),
      ],
    );
  }
}

class _OtherProfileActions extends StatelessWidget {
  const _OtherProfileActions({
    required this.profile,
    required this.busy,
    required this.ignored,
    required this.blocked,
    required this.onMessage,
    required this.onIgnoredChanged,
    required this.onBlockedChanged,
  });

  final MatrixUserProfile profile;
  final bool busy;
  final bool ignored;
  final bool blocked;
  final VoidCallback onMessage;
  final ValueChanged<bool> onIgnoredChanged;
  final ValueChanged<bool> onBlockedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.md,
            0,
            KiteSpacing.md,
            KiteSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('profile-message'),
              onPressed: busy ? null : onMessage,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Message'),
            ),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          key: const Key('profile-ignore'),
          value: ignored,
          onChanged: busy ? null : onIgnoredChanged,
          secondary: const Icon(Icons.volume_off_outlined),
          title: const Text('Ignore user'),
          subtitle: const Text('Hide messages and activity from this user.'),
        ),
        SwitchListTile(
          key: const Key('profile-block'),
          value: blocked,
          onChanged: busy ? null : onBlockedChanged,
          secondary: const Icon(Icons.block_outlined),
          title: const Text('Block user'),
          subtitle: const Text('Apply the homeserver-supported block state.'),
        ),
      ],
    );
  }
}

String _profileLabel(MatrixUserProfile profile) {
  final displayName = profile.displayName?.trim();
  return displayName == null || displayName.isEmpty
      ? profile.userId
      : displayName;
}

String _profileInitial(MatrixUserProfile profile) {
  final label = _profileLabel(profile);
  if (label.startsWith('@') && label.length > 1) return label[1].toUpperCase();
  return label.isEmpty ? '?' : label.characters.first.toUpperCase();
}
