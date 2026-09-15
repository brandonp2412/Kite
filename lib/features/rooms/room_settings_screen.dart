import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_management.dart';

class RoomSettingsScreen extends StatefulWidget {
  const RoomSettingsScreen({
    required this.roomId,
    required this.coordinator,
    this.avatarMedia,
    this.initialDetails,
    this.onSaved,
    super.key,
  });

  final String roomId;
  final RoomManagementCoordinator coordinator;
  final RoomAvatarMediaPort? avatarMedia;
  final KiteRoomDetails? initialDetails;
  final ValueChanged<KiteRoomDetails>? onSaved;

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  final _name = TextEditingController();
  final _topic = TextEditingController();
  final _alias = TextEditingController();
  KiteRoomDetails? _details;
  KiteRoomCapabilities? _capabilities;
  KiteRoomJoinRule _joinRule = KiteRoomJoinRule.invite;
  KiteRoomHistoryVisibility _historyVisibility =
      KiteRoomHistoryVisibility.joined;
  KiteRoomNotificationMode _notificationMode =
      KiteRoomNotificationMode.allMessages;
  Uri? _avatarUrl;
  bool _encryptionEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _avatarBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDetails;
    if (initial != null) {
      _applyDetails(initial);
      _loading = false;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        widget.coordinator.roomDetails(widget.roomId),
        widget.coordinator.capabilities(),
      ]);
      if (!mounted) return;
      final details = values[0] as KiteRoomDetails;
      final capabilities = values[1] as KiteRoomCapabilities;
      setState(() {
        _capabilities = capabilities;
        _applyDetails(details);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kite could not load room settings.';
      });
    }
  }

  void _applyDetails(KiteRoomDetails details) {
    _details = details;
    _name.text = details.name ?? '';
    _topic.text = details.topic ?? '';
    _alias.text = details.canonicalAlias ?? '';
    _avatarUrl = details.avatarUrl;
    _joinRule = details.joinRule;
    _historyVisibility = details.historyVisibility;
    _notificationMode = details.notificationMode;
    _encryptionEnabled = details.encryptionEnabled;
  }

  Future<void> _chooseAvatar() async {
    final media = widget.avatarMedia;
    if (media == null || _avatarBusy || _saving) return;
    setState(() {
      _avatarBusy = true;
      _error = null;
    });
    try {
      final selection = await media.chooseAndUploadAvatar(
        roomId: widget.roomId,
        currentAvatarUrl: _avatarUrl,
      );
      if (!mounted || selection == null) return;
      final avatarUrl = selection.avatarUrl;
      if (avatarUrl != null && avatarUrl.scheme != 'mxc') {
        setState(
          () => _error =
              'Room avatars must use an mxc URI supplied by the Matrix SDK.',
        );
        return;
      }
      setState(() => _avatarUrl = avatarUrl);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kite could not prepare the room avatar.');
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _removeAvatar() {
    if (_avatarBusy || _saving || _avatarUrl == null) return;
    setState(() {
      _avatarUrl = null;
      _error = null;
    });
  }

  Future<void> _save() async {
    final previous = _details;
    if (previous == null || _saving) return;
    FocusScope.of(context).unfocus();
    _saving = true;
    if (_error != null) {
      setState(() => _error = null);
    }

    final name = _optionalText(_name.text);
    final topic = _optionalText(_topic.text);
    final alias = _optionalText(_alias.text);
    try {
      if (name != previous.name) {
        await widget.coordinator.setName(roomId: widget.roomId, name: name);
      }
      if (topic != previous.topic) {
        await widget.coordinator.setTopic(roomId: widget.roomId, topic: topic);
      }
      if (_avatarUrl != previous.avatarUrl) {
        await widget.coordinator.setAvatar(
          roomId: widget.roomId,
          avatarUrl: _avatarUrl,
        );
      }
      if (!previous.isDirect && alias != previous.canonicalAlias) {
        await widget.coordinator.setCanonicalAlias(
          roomId: widget.roomId,
          canonicalAlias: alias,
        );
      }
      if (!previous.isDirect && _joinRule != previous.joinRule) {
        await widget.coordinator.setJoinRule(
          roomId: widget.roomId,
          joinRule: _joinRule,
        );
      }
      if (!previous.encryptionEnabled && _encryptionEnabled) {
        await widget.coordinator.enableEncryption(widget.roomId);
      }
      if (_historyVisibility != previous.historyVisibility) {
        await widget.coordinator.setHistoryVisibility(
          roomId: widget.roomId,
          visibility: _historyVisibility,
        );
      }
      if (_notificationMode != previous.notificationMode) {
        await widget.coordinator.setNotificationMode(
          roomId: widget.roomId,
          mode: _notificationMode,
        );
      }

      final saved = KiteRoomDetails(
        roomId: previous.roomId,
        name: name,
        topic: topic,
        avatarUrl: _avatarUrl,
        canonicalAlias: previous.isDirect ? previous.canonicalAlias : alias,
        joinRule: previous.isDirect ? previous.joinRule : _joinRule,
        encryptionEnabled: previous.encryptionEnabled || _encryptionEnabled,
        historyVisibility: _historyVisibility,
        notificationMode: _notificationMode,
        isDirect: previous.isDirect,
        directUserIds: previous.directUserIds,
      );
      if (!mounted) return;
      final encryptionBecamePersistent =
          !previous.encryptionEnabled && saved.encryptionEnabled;
      _details = saved;
      _encryptionEnabled = saved.encryptionEnabled;
      if (encryptionBecamePersistent) {
        setState(() {});
      }
      widget.onSaved?.call(saved);
    } on RoomManagementValidationException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kite could not save room settings.');
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      key: const Key('room-settings-screen'),
      appBar: AppBar(title: const Text('Room settings')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: details == null
                ? _LoadingOrFailure(
                    loading: _loading,
                    error: _error,
                    onRetry: _load,
                  )
                : ListView(
                    key: const Key('room-settings-form'),
                    padding: const EdgeInsets.all(KiteSpacing.lg),
                    children: <Widget>[
                      const _SectionTitle('Room profile'),
                      const SizedBox(height: KiteSpacing.sm),
                      if (widget.avatarMedia != null) ...<Widget>[
                        _RoomAvatarEditor(
                          avatarUrl: _avatarUrl,
                          busy: _avatarBusy,
                          onChoose: _chooseAvatar,
                          onRemove: _avatarUrl == null ? null : _removeAvatar,
                        ),
                        const SizedBox(height: KiteSpacing.md),
                      ],
                      TextField(
                        key: const Key('room-settings-name'),
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Room name',
                          prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: KiteSpacing.md),
                      TextField(
                        key: const Key('room-settings-topic'),
                        controller: _topic,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Topic',
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (!details.isDirect) ...<Widget>[
                        const SizedBox(height: KiteSpacing.md),
                        TextField(
                          key: const Key('room-settings-alias'),
                          controller: _alias,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Room address',
                            hintText: '#room:server',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                        const SizedBox(height: KiteSpacing.xl),
                        const _SectionTitle('Access'),
                        const SizedBox(height: KiteSpacing.sm),
                        DropdownButtonFormField<KiteRoomJoinRule>(
                          key: const Key('room-settings-join-rule'),
                          initialValue: _joinRule,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Who can join',
                          ),
                          items: <DropdownMenuItem<KiteRoomJoinRule>>[
                            for (final rule in _supportedJoinRules)
                              DropdownMenuItem<KiteRoomJoinRule>(
                                value: rule,
                                enabled: _supportsJoinRule(rule),
                                child: Text(_joinRuleLabel(rule)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null && _supportsJoinRule(value)) {
                              setState(() => _joinRule = value);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: KiteSpacing.xl),
                      const _SectionTitle('Privacy'),
                      const SizedBox(height: KiteSpacing.sm),
                      SwitchListTile.adaptive(
                        key: const Key('room-settings-encryption'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Encrypt messages'),
                        subtitle: Text(
                          _encryptionEnabled
                              ? 'End-to-end encryption is enabled and cannot be turned off.'
                              : 'Enable Matrix end-to-end encryption for future messages.',
                        ),
                        value: _encryptionEnabled,
                        onChanged: details.encryptionEnabled
                            ? null
                            : (value) {
                                if (value) {
                                  setState(() => _encryptionEnabled = true);
                                }
                              },
                      ),
                      const SizedBox(height: KiteSpacing.sm),
                      DropdownButtonFormField<KiteRoomHistoryVisibility>(
                        key: const Key('room-settings-history'),
                        initialValue: _historyVisibility,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Who can read history',
                        ),
                        items: <DropdownMenuItem<KiteRoomHistoryVisibility>>[
                          for (final visibility
                              in KiteRoomHistoryVisibility.values)
                            DropdownMenuItem<KiteRoomHistoryVisibility>(
                              value: visibility,
                              child: Text(_historyLabel(visibility)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _historyVisibility = value);
                          }
                        },
                      ),
                      const SizedBox(height: KiteSpacing.xl),
                      const _SectionTitle('Notifications'),
                      const SizedBox(height: KiteSpacing.sm),
                      DropdownButtonFormField<KiteRoomNotificationMode>(
                        key: const Key('room-settings-notifications'),
                        initialValue: _notificationMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Notify me for',
                        ),
                        items: <DropdownMenuItem<KiteRoomNotificationMode>>[
                          for (final mode in KiteRoomNotificationMode.values)
                            DropdownMenuItem<KiteRoomNotificationMode>(
                              value: mode,
                              child: Text(_notificationLabel(mode)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _notificationMode = value);
                          }
                        },
                      ),
                      const SizedBox(height: KiteSpacing.md),
                      SizedBox(
                        key: const Key('room-settings-error-slot'),
                        height: 48,
                        child: Center(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error ?? '',
                              key: const Key('room-settings-error'),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: KiteTypography.metadata.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: KiteSpacing.sm),
                      RepaintBoundary(
                        child: FilledButton.icon(
                          key: const Key('room-settings-save'),
                          style: const ButtonStyle(
                            animationDuration: Duration.zero,
                            overlayColor: WidgetStatePropertyAll<Color>(
                              Colors.transparent,
                            ),
                            splashFactory: NoSplash.splashFactory,
                          ),
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Iterable<KiteRoomJoinRule> get _supportedJoinRules sync* {
    final capabilities = _capabilities;
    for (final rule in KiteRoomJoinRule.values) {
      if (rule == KiteRoomJoinRule.public &&
          !(capabilities?.canCreatePublicRooms ?? false)) {
        continue;
      }
      if (rule == _joinRule || (capabilities?.supports(rule) ?? false)) {
        yield rule;
      }
    }
  }

  bool _supportsJoinRule(KiteRoomJoinRule rule) {
    if (rule == _joinRule) return true;
    final capabilities = _capabilities;
    if (capabilities == null) return false;
    if (rule == KiteRoomJoinRule.public && !capabilities.canCreatePublicRooms) {
      return false;
    }
    return capabilities.supports(rule);
  }
}

class _RoomAvatarEditor extends StatelessWidget {
  const _RoomAvatarEditor({
    required this.avatarUrl,
    required this.busy,
    required this.onChoose,
    required this.onRemove,
  });

  final Uri? avatarUrl;
  final bool busy;
  final VoidCallback onChoose;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Room avatar',
      child: Row(
        key: const Key('room-settings-avatar-editor'),
        children: <Widget>[
          CircleAvatar(
            key: const Key('room-settings-avatar-preview'),
            radius: 28,
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            child: Icon(
              avatarUrl == null ? Icons.group_outlined : Icons.group_rounded,
              size: 28,
            ),
          ),
          const SizedBox(width: KiteSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  avatarUrl == null ? 'No room avatar' : 'Room avatar selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KiteTypography.metadata,
                ),
                const SizedBox(height: KiteSpacing.xs),
                Wrap(
                  spacing: KiteSpacing.sm,
                  runSpacing: KiteSpacing.xs,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const Key('room-settings-avatar-choose'),
                      onPressed: busy ? null : onChoose,
                      icon: SizedBox.square(
                        dimension: 18,
                        child: busy
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.photo_outlined, size: 18),
                      ),
                      label: Text(
                        avatarUrl == null ? 'Choose photo' : 'Replace',
                      ),
                    ),
                    if (avatarUrl != null)
                      TextButton.icon(
                        key: const Key('room-settings-avatar-remove'),
                        onPressed: busy ? null : onRemove,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: KiteTypography.title);
  }
}

class _LoadingOrFailure extends StatelessWidget {
  const _LoadingOrFailure({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox.square(
          key: Key('room-settings-loading'),
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KiteSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(error ?? 'Room settings are unavailable.'),
            const SizedBox(height: KiteSpacing.md),
            FilledButton.tonal(
              key: const Key('room-settings-retry'),
              onPressed: () => unawaited(onRetry()),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _optionalText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _joinRuleLabel(KiteRoomJoinRule rule) => switch (rule) {
  KiteRoomJoinRule.invite => 'Invite only',
  KiteRoomJoinRule.public => 'Anyone',
  KiteRoomJoinRule.knock => 'Request to join',
  KiteRoomJoinRule.restricted => 'Members of allowed Spaces',
};

String _historyLabel(KiteRoomHistoryVisibility visibility) =>
    switch (visibility) {
      KiteRoomHistoryVisibility.invited => 'Members from invite',
      KiteRoomHistoryVisibility.joined => 'Members from join',
      KiteRoomHistoryVisibility.shared => 'Members before they joined',
      KiteRoomHistoryVisibility.worldReadable => 'Anyone',
    };

String _notificationLabel(KiteRoomNotificationMode mode) => switch (mode) {
  KiteRoomNotificationMode.allMessages => 'All messages',
  KiteRoomNotificationMode.mentionsOnly => 'Mentions only',
  KiteRoomNotificationMode.mute => 'Nothing',
};
