import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_scope_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:signals/signals_flutter.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({
    required this.accountController,
    required this.sessionDeviceController,
    this.securityScopeController,
    this.onAddAccount,
    this.onActiveAccountChanged,
    this.onActiveAccountSignedOut,
    this.loadOnInit = true,
    super.key,
  });

  final AccountManagementController accountController;
  final SessionDeviceController sessionDeviceController;
  final AccountSecurityScopeController? securityScopeController;
  final VoidCallback? onAddAccount;
  final ValueChanged<ManagedMatrixAccount>? onActiveAccountChanged;
  final VoidCallback? onActiveAccountSignedOut;
  final bool loadOnInit;

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      unawaited(_loadInitialState());
    }
  }

  Future<void> _loadInitialState() async {
    await widget.accountController.load();
    if (!mounted) return;
    final active = widget.accountController.activeAccount;
    if (active == null) {
      widget.securityScopeController?.resetForAccountChange();
      widget.sessionDeviceController.resetForAccountChange();
      return;
    }

    final securityScope = widget.securityScopeController;
    if (securityScope != null) {
      await securityScope.resetAndRefreshActiveAccount(
        currentDeviceId: active.session.deviceId,
      );
    } else {
      widget.sessionDeviceController.resetForAccountChange();
      await widget.sessionDeviceController.load(
        expectedCurrentDeviceId: active.session.deviceId,
      );
    }
  }

  Future<bool> _confirm({
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
            key: Key('account-security-confirm-$actionLabel'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _activateAccount(ManagedMatrixAccount account) async {
    final activated = await widget.accountController.activate(
      account.accountId,
    );
    if (!activated) return;

    final active = widget.accountController.activeAccount;
    final securityScope = widget.securityScopeController;
    if (securityScope != null) {
      await securityScope.resetAndRefreshActiveAccount(
        currentDeviceId: active?.session.deviceId,
      );
    } else if (widget.sessionDeviceController.resetForAccountChange()) {
      await widget.sessionDeviceController.load(
        expectedCurrentDeviceId: active?.session.deviceId,
      );
    }
    if (!mounted) return;

    if (active != null) {
      widget.onActiveAccountChanged?.call(active);
    }
  }

  Future<void> _signOutAccount(ManagedMatrixAccount account) async {
    final confirmed = await _confirm(
      title: 'Sign out ${_accountLabel(account)}?',
      message: account.isActive
          ? 'This will sign out the current account and return Kite to account selection.'
          : 'This removes only this account and its isolated local session data.',
      actionLabel: 'Sign out',
    );
    if (!confirmed) return;
    final signedOut = await widget.accountController.signOut(account.accountId);
    if (signedOut && account.isActive) {
      final securityScope = widget.securityScopeController;
      if (securityScope != null) {
        securityScope.resetForAccountChange();
      } else {
        widget.sessionDeviceController.resetForAccountChange();
      }
      widget.onActiveAccountSignedOut?.call();
    }
  }

  Future<void> _signOutDevice(SessionDevice device) async {
    final confirmed = await _confirm(
      title: 'Sign out ${device.displayName ?? device.deviceId}?',
      message: 'This Matrix session will be remotely signed out.',
      actionLabel: 'Sign out device',
    );
    if (!confirmed) return;
    await widget.sessionDeviceController.signOutRemoteDevice(device.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & sessions')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final accounts = widget.accountController.accounts.value;
            final accountLoading = widget.accountController.isLoading.value;
            final busyAccounts = widget.accountController.busyAccountIds.value;
            final accountOperationActive = busyAccounts.isNotEmpty;
            final accountError = widget.accountController.errorMessage.value;
            final devices = widget.sessionDeviceController.devices.value;
            final deviceLoading =
                widget.sessionDeviceController.isLoading.value;
            final signingOutDevices =
                widget.sessionDeviceController.signingOutDeviceIds.value;
            final deviceOperationActive =
                deviceLoading || signingOutDevices.isNotEmpty;
            final securityOperationActive =
                accountOperationActive || deviceOperationActive;
            final deviceError =
                widget.sessionDeviceController.errorMessage.value;

            return ListView(
              key: const Key('account-security-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                _SectionTitle(
                  label: 'Accounts',
                  action: widget.onAddAccount == null
                      ? null
                      : TextButton.icon(
                          key: const Key('add-account'),
                          onPressed: securityOperationActive
                              ? null
                              : widget.onAddAccount,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add account'),
                        ),
                ),
                SizedBox(
                  key: const Key('account-loading-slot'),
                  height: 4,
                  child: accountLoading
                      ? const LinearProgressIndicator()
                      : null,
                ),
                if (accounts.isEmpty && !accountLoading)
                  const _EmptyRow(
                    key: Key('account-empty'),
                    icon: Icons.person_off_outlined,
                    label: 'No signed-in accounts',
                  )
                else
                  for (final account in accounts)
                    _AccountTile(
                      account: account,
                      busy: securityOperationActive,
                      onActivate: account.isActive
                          ? null
                          : () => _activateAccount(account),
                      onSignOut: () => _signOutAccount(account),
                    ),
                const Divider(height: 1),
                const _SectionTitle(label: 'Sessions'),
                SizedBox(
                  key: const Key('device-loading-slot'),
                  height: 4,
                  child: deviceLoading ? const LinearProgressIndicator() : null,
                ),
                if (devices.isEmpty && !deviceLoading)
                  const _EmptyRow(
                    key: Key('device-empty'),
                    icon: Icons.devices_other_outlined,
                    label: 'No signed-in devices',
                  )
                else
                  for (final device in devices)
                    _DeviceTile(
                      device: device,
                      busy:
                          accountOperationActive ||
                          signingOutDevices.contains(device.deviceId),
                      onSignOut: device.isCurrent
                          ? null
                          : () => _signOutDevice(device),
                    ),
                SizedBox(
                  key: const Key('account-security-status'),
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
                          accountError ?? deviceError ?? '',
                          style: KiteTypography.metadata.copyWith(
                            color: accountError == null && deviceError == null
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

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.busy,
    required this.onActivate,
    required this.onSignOut,
  });

  final ManagedMatrixAccount account;
  final bool busy;
  final VoidCallback? onActivate;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('account-${account.accountId}'),
      minTileHeight: 76,
      leading: CircleAvatar(child: Text(_accountInitial(account))),
      title: Text(
        _accountLabel(account),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${account.session.userId} · ${account.session.homeserver.displayName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (account.isActive)
            const _StateBadge(
              key: Key('active-account-badge'),
              label: 'Current',
            )
          else
            TextButton(
              key: Key('activate-account-${account.accountId}'),
              onPressed: busy ? null : onActivate,
              child: const Text('Switch'),
            ),
          IconButton(
            key: Key('sign-out-account-${account.accountId}'),
            tooltip: 'Sign out account',
            onPressed: busy ? null : onSignOut,
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.busy,
    required this.onSignOut,
  });

  final SessionDevice device;
  final bool busy;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('device-${device.deviceId}'),
      minTileHeight: 76,
      leading: Icon(
        device.isCurrent ? Icons.smartphone : Icons.devices_other_outlined,
      ),
      title: Text(
        device.displayName ?? device.deviceId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${device.deviceId} · ${_verificationLabel(device.verification)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: 116,
        child: Align(
          alignment: Alignment.centerRight,
          child: device.isCurrent
              ? const _StateBadge(
                  key: Key('current-device-badge'),
                  label: 'This device',
                )
              : TextButton(
                  key: Key('sign-out-device-${device.deviceId}'),
                  onPressed: busy ? null : onSignOut,
                  child: Text(busy ? 'Signing out…' : 'Sign out'),
                ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(KiteRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KiteSpacing.sm,
          vertical: KiteSpacing.xs,
        ),
        child: Text(label, style: KiteTypography.metadata),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        KiteSpacing.lg,
        KiteSpacing.md,
        KiteSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: KiteTypography.title)),
          ?action,
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: KiteSpacing.sm),
            Text(label, style: KiteTypography.metadata),
          ],
        ),
      ),
    );
  }
}

String _accountLabel(ManagedMatrixAccount account) {
  final displayName = account.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return account.session.userId;
}

String _accountInitial(ManagedMatrixAccount account) {
  final label = _accountLabel(account);
  if (label.startsWith('@') && label.length > 1) {
    return label[1].toUpperCase();
  }
  return label.isEmpty ? '?' : label[0].toUpperCase();
}

String _verificationLabel(SessionDeviceVerification verification) {
  return switch (verification) {
    SessionDeviceVerification.verified => 'Verified',
    SessionDeviceVerification.unverified => 'Unverified',
    SessionDeviceVerification.unknown => 'Verification unknown',
  };
}
