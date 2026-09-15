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
    required this.onOpenRoom,
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
    _loadProfileIfEnabled();
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        oldWidget.userId == widget.userId) {
      return;
    }
    _loadProfileIfEnabled();
  }

  void _loadProfileIfEnabled() {
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
    final focusNode = FocusNode();
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          key: const Key('profile-display-name-field'),
          controller: textController,
          focusNode: focusNode,
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
    final routeFuture = Navigator.of(context, rootNavigator: true).push(route);
    await Future<void>.delayed(route.transitionDuration);
    if (mounted && route.isActive) {
      focusNode.requestFocus();
    }
    final next = await routeFuture;
    if (next != null && mounted) {
      await widget.controller.updateDisplayName(next);
    }
    await route.completed;
    focusNode.dispose();
    textController.dispose();
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
      widget.onOpenRoom!(roomId);
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
            final privacyLoading = widget.controller.isPrivacyLoading.value;
            final hasPrivacyState = widget.controller.hasPrivacyState.value;
            final saving = widget.controller.isSaving.value;
            final error = widget.controller.errorMessage.value;
            final busy = loading || saving;
            final privacyBusy = privacyLoading || saving || !hasPrivacyState;

            return ListView(
              key: const Key('user-profile-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('profile-loading-slot'),
                  height: 4,
                  child: loading || privacyLoading
                      ? const LinearProgressIndicator()
                      : null,
                ),
                if (profile == null)
                  _ProfilePlaceholder(
                    isOwnProfile: widget.isOwnProfile,
                    canChangeAvatar: widget.pickAvatar != null,
                    loading: loading,
                  )
                else
                  _ProfileContent(
                    profile: profile,
                    isOwnProfile: widget.isOwnProfile,
                    busy: busy,
                    privacyBusy: privacyBusy,
                    canChangeAvatar: widget.pickAvatar != null,
                    imageProvider: widget.avatarImageProvider?.call(
                      profile.avatarUri,
                    ),
                    ignored: widget.controller.isIgnored(profile.userId),
                    blocked: widget.controller.isBlocked(profile.userId),
                    onEditDisplayName: () => _editDisplayName(profile),
                    onChangeAvatar: _changeAvatar,
                    onRemoveAvatar: profile.avatarUri == null
                        ? null
                        : () => widget.controller.updateAvatar(null),
                    onMessage: () => _openDirectMessage(profile),
                    onIgnoredChanged: (value) =>
                        widget.controller.setIgnored(profile.userId, value),
                    onBlockedChanged: (value) =>
                        widget.controller.setBlocked(profile.userId, value),
                  ),
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

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder({
    required this.isOwnProfile,
    required this.canChangeAvatar,
    required this.loading,
  });

  final bool isOwnProfile;
  final bool canChangeAvatar;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const placeholderProfile = MatrixUserProfile(
      userId: '@loading:example.org',
      displayName: 'Loading profile',
      avatarUri: null,
    );
    return Stack(
      key: const Key('profile-content-slot'),
      children: <Widget>[
        Visibility(
          visible: false,
          maintainAnimation: true,
          maintainSize: true,
          maintainState: true,
          child: _ProfileContent(
            profile: placeholderProfile,
            isOwnProfile: isOwnProfile,
            busy: true,
            privacyBusy: true,
            canChangeAvatar: canChangeAvatar,
            imageProvider: null,
            ignored: false,
            blocked: false,
            onEditDisplayName: _noop,
            onChangeAvatar: _noop,
            onRemoveAvatar: null,
            onMessage: _noop,
            onIgnoredChanged: _noopBool,
            onBlockedChanged: _noopBool,
            keyed: false,
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Text(
              loading ? 'Loading profile…' : 'Profile unavailable',
              key: const Key('profile-empty-state'),
              style: KiteTypography.body,
            ),
          ),
        ),
      ],
    );
  }

  static void _noop() {}
  static void _noopBool(bool _) {}
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.isOwnProfile,
    required this.busy,
    required this.privacyBusy,
    required this.canChangeAvatar,
    required this.imageProvider,
    required this.ignored,
    required this.blocked,
    required this.onEditDisplayName,
    required this.onChangeAvatar,
    required this.onRemoveAvatar,
    required this.onMessage,
    required this.onIgnoredChanged,
    required this.onBlockedChanged,
    this.keyed = true,
  });

  final MatrixUserProfile profile;
  final bool isOwnProfile;
  final bool busy;
  final bool privacyBusy;
  final bool canChangeAvatar;
  final ImageProvider<Object>? imageProvider;
  final bool ignored;
  final bool blocked;
  final VoidCallback onEditDisplayName;
  final VoidCallback onChangeAvatar;
  final VoidCallback? onRemoveAvatar;
  final VoidCallback onMessage;
  final ValueChanged<bool> onIgnoredChanged;
  final ValueChanged<bool> onBlockedChanged;
  final bool keyed;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: keyed ? const Key('profile-content-slot') : null,
      children: <Widget>[
        _ProfileHeader(profile: profile, imageProvider: imageProvider),
        if (isOwnProfile)
          _OwnProfileActions(
            profile: profile,
            busy: busy,
            canChangeAvatar: canChangeAvatar,
            onEditDisplayName: onEditDisplayName,
            onChangeAvatar: onChangeAvatar,
            onRemoveAvatar: onRemoveAvatar,
          )
        else
          _OtherProfileActions(
            profile: profile,
            busy: busy,
            privacyBusy: privacyBusy,
            ignored: ignored,
            blocked: blocked,
            onMessage: onMessage,
            onIgnoredChanged: onIgnoredChanged,
            onBlockedChanged: onBlockedChanged,
          ),
      ],
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
        Visibility(
          visible: profile.avatarUri != null,
          maintainAnimation: true,
          maintainSize: true,
          maintainState: true,
          child: ListTile(
            key: const Key('remove-profile-avatar'),
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Remove avatar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: !busy && profile.avatarUri != null,
            onTap: busy || profile.avatarUri == null ? null : onRemoveAvatar,
          ),
        ),
      ],
    );
  }
}

class _OtherProfileActions extends StatelessWidget {
  const _OtherProfileActions({
    required this.profile,
    required this.busy,
    required this.privacyBusy,
    required this.ignored,
    required this.blocked,
    required this.onMessage,
    required this.onIgnoredChanged,
    required this.onBlockedChanged,
  });

  final MatrixUserProfile profile;
  final bool busy;
  final bool privacyBusy;
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
          onChanged: busy || privacyBusy ? null : onIgnoredChanged,
          secondary: const Icon(Icons.volume_off_outlined),
          title: const Text('Ignore user'),
          subtitle: const Text('Hide messages and activity from this user.'),
        ),
        SwitchListTile(
          key: const Key('profile-block'),
          value: blocked,
          onChanged: busy || privacyBusy ? null : onBlockedChanged,
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
