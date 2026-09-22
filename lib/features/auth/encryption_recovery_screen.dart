import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:signals/signals_flutter.dart';

class EncryptionRecoveryScreen extends StatefulWidget {
  const EncryptionRecoveryScreen({
    required this.controller,
    this.loadOnInit = true,
    this.selectRoomKeyBackup,
    super.key,
  });

  final EncryptionRecoveryController controller;
  final bool loadOnInit;
  final Future<XFile?> Function()? selectRoomKeyBackup;

  @override
  State<EncryptionRecoveryScreen> createState() =>
      _EncryptionRecoveryScreenState();
}

class _EncryptionRecoveryScreenState extends State<EncryptionRecoveryScreen> {
  late final TextEditingController _recoveryKeyController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _roomKeyBackupPassphraseController;
  XFile? _selectedRoomKeyBackup;

  @override
  void initState() {
    super.initState();
    _recoveryKeyController = TextEditingController();
    _passphraseController = TextEditingController();
    _roomKeyBackupPassphraseController = TextEditingController();
    if (widget.loadOnInit) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    _clearSecrets();
    _roomKeyBackupPassphraseController.clear();
    _recoveryKeyController.dispose();
    _passphraseController.dispose();
    _roomKeyBackupPassphraseController.dispose();
    super.dispose();
  }

  void _clearSecrets() {
    _recoveryKeyController.clear();
    _passphraseController.clear();
  }

  Future<void> _restoreWithRecoveryKey() async {
    final recoveryKey = _recoveryKeyController.text;
    _clearSecrets();
    await widget.controller.restoreWithRecoveryKey(recoveryKey);
  }

  Future<void> _restoreWithPassphrase() async {
    final passphrase = _passphraseController.text;
    _clearSecrets();
    await widget.controller.restoreWithPassphrase(passphrase);
  }

  Future<void> _selectRoomKeyBackup() async {
    final selected = await (widget.selectRoomKeyBackup?.call() ?? openFile());
    if (!mounted || selected == null) return;
    setState(() => _selectedRoomKeyBackup = selected);
  }

  Future<void> _importRoomKeyBackup() async {
    final passphrase = _roomKeyBackupPassphraseController.text;
    _roomKeyBackupPassphraseController.clear();
    final imported = await widget.controller.importRoomKeyBackup(
      path: _selectedRoomKeyBackup?.path ?? '',
      passphrase: passphrase,
    );
    if (!mounted || !imported) return;
    setState(() => _selectedRoomKeyBackup = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encryption recovery')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('encryption-recovery-list'),
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.md,
            KiteSpacing.sm,
            KiteSpacing.md,
            KiteSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _RecoveryOverviewSignal(controller: widget.controller),
              const SizedBox(height: KiteSpacing.md),
              SizedBox(
                height: 88,
                child: SignalBuilder(
                  builder: (context) {
                    final busy = widget.controller.isBusy.value;
                    final operation = widget.controller.activeOperation.value;
                    final success = widget.controller.successMessage.value;
                    return busy || success != null
                        ? _RecoveryOperationFeedback(
                            busy: busy,
                            operation: operation,
                            success: success,
                          )
                        : const SizedBox.shrink(
                            key: Key(
                              'encryption-recovery-feedback-placeholder',
                            ),
                          );
                  },
                ),
              ),
              const SizedBox(height: KiteSpacing.md),
              _RecoveryActionBlocker(
                controller: widget.controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _RecoveryCard(
                      icon: Icons.key_rounded,
                      eyebrow: 'Recommended',
                      title: 'Restore with your recovery key',
                      detail: 'Use the recovery key from your Matrix account. Kite sends it directly to the Matrix SDK and does not store it.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            key: const Key('recovery-key-field'),
                            controller: _recoveryKeyController,
                            enabled: true,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const <String>[],
                            decoration: const InputDecoration(
                              labelText: 'Recovery key',
                              hintText: 'Enter recovery key',
                            ),
                            onSubmitted: (_) => _restoreWithRecoveryKey(),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          FilledButton.icon(
                            key: const Key('restore-recovery-key'),
                            onPressed: _restoreWithRecoveryKey,
                            icon: const Icon(Icons.lock_open_rounded),
                            label: const Text('Restore encrypted messages'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KiteSpacing.md),
                    _RecoveryBackupCard(controller: widget.controller),
                    const SizedBox(height: KiteSpacing.md),
                    _RecoveryHistoryCard(controller: widget.controller),
                    const SizedBox(height: KiteSpacing.md),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: const Key('encryption-recovery-other-methods'),
                        leading: const Icon(Icons.more_horiz_rounded),
                        title: const Text('Other recovery methods'),
                        subtitle: const Text(
                          'Use a recovery passphrase or an Element room-key export.',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          KiteSpacing.md,
                          0,
                          KiteSpacing.md,
                          KiteSpacing.md,
                        ),
                        children: <Widget>[
                          const Divider(height: 1),
                          const SizedBox(height: KiteSpacing.md),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Recovery passphrase',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.xs),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Use this only if your Matrix backup was configured with a passphrase.',
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          TextField(
                            key: const Key('recovery-passphrase-field'),
                            controller: _passphraseController,
                            enabled: true,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const <String>[],
                            decoration: const InputDecoration(
                              labelText: 'Recovery passphrase',
                            ),
                            onSubmitted: (_) => _restoreWithPassphrase(),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              key: const Key('restore-passphrase'),
                              onPressed: _restoreWithPassphrase,
                              child: const Text('Restore with passphrase'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: KiteSpacing.md,
                            ),
                            child: Divider(height: 1),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Element room-key export',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.xs),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Import an encrypted E2EE key export created by Element.',
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          OutlinedButton.icon(
                            key: const Key('select-room-key-backup'),
                            onPressed: _selectRoomKeyBackup,
                            icon: const Icon(Icons.file_open_outlined),
                            label: Text(
                              _selectedRoomKeyBackup?.name ??
                                  'Choose room-key backup',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          TextField(
                            key: const Key('room-key-backup-passphrase-field'),
                            controller: _roomKeyBackupPassphraseController,
                            enabled: true,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const <String>[],
                            decoration: const InputDecoration(
                              labelText: 'Export passphrase',
                            ),
                            onSubmitted: (_) => _importRoomKeyBackup(),
                          ),
                          const SizedBox(height: KiteSpacing.sm),
                          FilledButton.icon(
                            key: const Key('import-room-key-backup'),
                            onPressed: _importRoomKeyBackup,
                            icon: const Icon(Icons.key_rounded),
                            label: const Text('Import room keys'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _RecoveryErrorStatus(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryOverviewSignal extends StatelessWidget {
  const _RecoveryOverviewSignal({required this.controller});

  final EncryptionRecoveryController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) => _RecoveryOverview(
        status: controller.status.value,
        error: controller.errorMessage.value,
      ),
    );
  }
}

class _RecoveryBackupCard extends StatelessWidget {
  const _RecoveryBackupCard({required this.controller});

  final EncryptionRecoveryController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final backupReady =
            controller.status.value?.backupState == EncryptedBackupState.ready;
        return _RecoveryCard(
          icon: backupReady
              ? Icons.cloud_done_rounded
              : Icons.cloud_upload_outlined,
          title: backupReady
              ? 'Encrypted backup is ready'
              : 'Protect future message history',
          detail: backupReady
              ? 'This account has an encrypted Matrix key backup available.'
              : 'Enable encrypted backup so this account can recover encrypted message history on another device.',
          child: backupReady
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.check_circle_rounded),
                    SizedBox(width: KiteSpacing.sm),
                    Text('Encrypted backup enabled'),
                  ],
                )
              : FilledButton.tonalIcon(
                  key: const Key('create-encrypted-backup'),
                  onPressed: controller.createEncryptedBackup,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Enable encrypted backup'),
                ),
        );
      },
    );
  }
}

class _RecoveryHistoryCard extends StatelessWidget {
  const _RecoveryHistoryCard({required this.controller});

  final EncryptionRecoveryController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final status = controller.status.value;
        return _RecoveryCard(
          icon: Icons.history_rounded,
          title: 'Message history',
          detail: _historyDetail(status),
          child: OutlinedButton.icon(
            key: const Key('recover-history'),
            onPressed:
                status?.historicalRecoveryState !=
                    HistoricalRecoveryState.available
                ? null
                : controller.recoverHistoricalMessages,
            icon: const Icon(Icons.history_rounded),
            label: const Text('Recover encrypted history'),
          ),
        );
      },
    );
  }
}

class _RecoveryErrorStatus extends StatelessWidget {
  const _RecoveryErrorStatus({required this.controller});

  final EncryptionRecoveryController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('encryption-recovery-status-slot'),
      height: 72,
      child: Padding(
        padding: const EdgeInsets.only(top: KiteSpacing.md),
        child: SignalBuilder(
          builder: (context) {
            final error = controller.errorMessage.value;
            return Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: KiteMotion.resolve(context, KiteMotion.standard),
                child: Text(
                  error ?? '',
                  key: const Key('encryption-recovery-error'),
                  style: KiteTypography.metadata.copyWith(
                    color: error == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecoveryActionBlocker extends StatelessWidget {
  const _RecoveryActionBlocker({required this.controller, required this.child});

  final EncryptionRecoveryController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) =>
          IgnorePointer(ignoring: controller.isBusy.value, child: child),
    );
  }
}

class _RecoveryOperationFeedback extends StatelessWidget {
  const _RecoveryOperationFeedback({
    required this.busy,
    required this.operation,
    required this.success,
  });

  final bool busy;
  final EncryptionRecoveryOperation? operation;
  final String? success;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = busy
        ? switch (operation) {
            EncryptionRecoveryOperation.refreshStatus =>
              'Checking Matrix recovery status…',
            EncryptionRecoveryOperation.createBackup =>
              'Enabling encrypted backup…',
            EncryptionRecoveryOperation.restoreBackup =>
              'Restoring encrypted messages and downloading room keys…',
            EncryptionRecoveryOperation.recoverHistory =>
              'Recovering encrypted message history…',
            EncryptionRecoveryOperation.importRoomKeys =>
              'Importing room keys and reloading message history…',
            null => 'Working…',
          }
        : success ?? '';

    return Semantics(
      key: const Key('encryption-recovery-feedback'),
      liveRegion: true,
      label: message,
      child: Container(
        key: busy ? const Key('encryption-recovery-progress') : null,
        padding: const EdgeInsets.all(KiteSpacing.md),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: busy ? colors.surfaceContainerHigh : colors.primaryContainer,
          borderRadius: BorderRadius.circular(KiteRadii.md),
        ),
        child: Text(
          message,
          key: Key(
            busy
                ? 'encryption-recovery-progress-label'
                : 'encryption-recovery-success',
          ),
          style: KiteTypography.body.copyWith(
            color: busy ? colors.onSurface : colors.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RecoveryOverview extends StatelessWidget {
  const _RecoveryOverview({required this.status, required this.error});

  final EncryptionRecoveryStatus? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final backupState = status?.backupState;
    final colors = Theme.of(context).colorScheme;
    final (icon, title, detail) = error != null && backupState == null
        ? (
            Icons.error_outline_rounded,
            'Recovery status could not be checked',
            'Kite could not read the Matrix backup state. Retry when the connection is available.',
          )
        : switch (backupState) {
            EncryptedBackupState.ready => (
              Icons.verified_user_rounded,
              'Recovery is set up',
              'Encrypted backup is available for this account.',
            ),
            EncryptedBackupState.needsRecovery => (
              Icons.warning_amber_rounded,
              'Recovery needs attention',
              'Restore your encryption keys to read older encrypted messages.',
            ),
            EncryptedBackupState.unavailable => (
              Icons.cloud_off_outlined,
              'No encrypted backup found',
              'This session is active, but Matrix does not report an encrypted key backup for this account.',
            ),
            EncryptedBackupState.unknown => (
              Icons.sync_problem_rounded,
              'Recovery status is not available yet',
              'Matrix has not reported enough backup state to determine whether recovery is configured.',
            ),
            null => (
              Icons.shield_outlined,
              'Checking recovery setup',
              'Kite is checking the Matrix backup and session state.',
            ),
          };

    return RepaintBoundary(
      child: Container(
        key: const Key('encryption-recovery-summary'),
        padding: const EdgeInsets.all(KiteSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(KiteRadii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 28, color: colors.primary),
            const SizedBox(width: KiteSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: KiteSpacing.xs),
                  Text(detail),
                  if (status?.hasUnverifiedSessions ?? false) ...<Widget>[
                    const SizedBox(height: KiteSpacing.sm),
                    Text(
                      'Some signed-in sessions are not verified.',
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.child,
    this.eyebrow,
  });

  final IconData icon;
  final String? eyebrow;
  final String title;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(KiteSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, color: colors.primary),
                  const SizedBox(width: KiteSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (eyebrow != null) ...<Widget>[
                          Text(
                            eyebrow!.toUpperCase(),
                            style: KiteTypography.metadata.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.xxs),
                        ],
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: KiteSpacing.xxs),
                        Text(
                          detail,
                          style: KiteTypography.body.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KiteSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

String _historyDetail(EncryptionRecoveryStatus? status) {
  return switch (status?.historicalRecoveryState) {
    HistoricalRecoveryState.available => 'Recovered keys are available. Ask Matrix to retry older encrypted events.',
    HistoricalRecoveryState.recovering =>
      'Matrix is currently retrying encrypted message history.',
    HistoricalRecoveryState.complete =>
      'Encrypted message history has been recovered.',
    HistoricalRecoveryState.idle || null => 'Restore your encryption keys first. History recovery becomes available when Matrix has keys to retry.',
  };
}
