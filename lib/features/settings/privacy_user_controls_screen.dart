import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:signals/signals_flutter.dart';

class PrivacyUserControlsScreen extends StatefulWidget {
  const PrivacyUserControlsScreen({
    required this.controller,
    this.onOpenUser,
    this.loadOnInit = true,
    super.key,
  });

  final UserProfileController controller;
  final ValueChanged<String>? onOpenUser;
  final bool loadOnInit;

  @override
  State<PrivacyUserControlsScreen> createState() =>
      _PrivacyUserControlsScreenState();
}

class _PrivacyUserControlsScreenState extends State<PrivacyUserControlsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      unawaited(widget.controller.refreshPrivacyControls());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final blocked = widget.controller.blockedUserIds.value.toList()
              ..sort();
            final loading = widget.controller.isPrivacyLoading.value;
            final saving = widget.controller.isSaving.value;
            final hasPrivacyState = widget.controller.hasPrivacyState.value;
            final busy = loading || saving || !hasPrivacyState;
            final error = widget.controller.errorMessage.value;

            return ListView(
              key: const Key('privacy-user-controls-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('privacy-user-controls-loading-slot'),
                  height: 4,
                  child: loading ? const LinearProgressIndicator() : null,
                ),
                const _SectionTitle(label: 'Blocked users'),
                SizedBox(
                  key: const Key('blocked-users-slot'),
                  height: _sectionHeight(blocked.length),
                  child: blocked.isEmpty
                      ? const _EmptyState(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'No blocked users',
                        )
                      : ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: blocked.length,
                          itemExtent: 72,
                          itemBuilder: (context, index) {
                            final userId = blocked[index];
                            return _PrivacyUserTile(
                              key: Key('blocked-user-$userId'),
                              userId: userId,
                              actionKey: Key('unblock-user-$userId'),
                              actionLabel: 'Unblock',
                              busy: busy,
                              onOpenUser: widget.onOpenUser,
                              onAction: () =>
                                  widget.controller.setBlocked(userId, false),
                            );
                          },
                        ),
                ),
                SizedBox(
                  key: const Key('privacy-user-controls-status-slot'),
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

  static double _sectionHeight(int count) => count == 0 ? 72 : count * 72;
}

class _PrivacyUserTile extends StatelessWidget {
  const _PrivacyUserTile({
    required this.userId,
    required this.actionKey,
    required this.actionLabel,
    required this.busy,
    required this.onOpenUser,
    required this.onAction,
    super.key,
  });

  final String userId;
  final Key actionKey;
  final String actionLabel;
  final bool busy;
  final ValueChanged<String>? onOpenUser;
  final Future<bool> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      leading: CircleAvatar(child: Text(_initial(userId))),
      title: Text(userId, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onOpenUser == null || busy ? null : () => onOpenUser!(userId),
      trailing: TextButton(
        key: actionKey,
        onPressed: busy ? null : onAction,
        child: Text(actionLabel),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: KiteSpacing.sm),
          Text(label, style: KiteTypography.metadata),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        KiteSpacing.lg,
        KiteSpacing.md,
        KiteSpacing.sm,
      ),
      child: Text(label, style: KiteTypography.title),
    );
  }
}

String _initial(String userId) {
  if (userId.startsWith('@') && userId.length > 1) {
    return userId[1].toUpperCase();
  }
  return '?';
}
