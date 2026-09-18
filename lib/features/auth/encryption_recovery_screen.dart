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
        child: SignalBuilder(
          builder: (context) {
            final status = widget.controller.status.value;
            final importResult = widget.controller.roomKeyImportResult.value;
            final busy = widget.controller.isBusy.value;
            final error = widget.controller.errorMessage.value;
            final backupReady =
                status?.backupState == EncryptedBackupState.ready;

            return SingleChildScrollView(
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
                  _RecoveryOverview(status: status),
                  const SizedBox(height: KiteSpacing.md),
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
                          enabled: !busy,
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
                          onSubmitted: busy
                              ? null
                              : (_) => _restoreWithRecoveryKey(),
                        ),
                        const SizedBox(height: KiteSpacing.sm),
                        FilledButton.icon(
                          key: const Key('restore-recovery-key'),
                          onPressed: busy ? null : _restoreWithRecoveryKey,
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text('Restore encrypted messages'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: KiteSpacing.md),
                  _RecoveryCard(
                    icon: backupReady
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_upload_outlined,
                    title: backupReady
                        ? 'Encrypted backup is ready'
                        : 'Protect future message history',
                    detail: backupReady
                        ? 'This account has an encrypted Matrix key backup available.'
                        : 'Enable encrypted backup so this account can recover encrypted message history on another device.',
                    child: FilledButton.tonalIcon(
                      key: const Key('create-encrypted-backup'),
                      onPressed: busy || backupReady
                          ? null
                          : widget.controller.createEncryptedBackup,
                      icon: Icon(
                        backupReady
                            ? Icons.check_circle_rounded
                            : Icons.cloud_upload_outlined,
                      ),
                      label: Text(
                        backupReady
                            ? 'Encrypted backup enabled'
                            : 'Enable encrypted backup',
                      ),
                    ),
                  ),
                  const SizedBox(height: KiteSpacing.md),
                  _RecoveryCard(
                    icon: Icons.history_rounded,
                    title: 'Message history',
                    detail: _historyDetail(status),
                    child: OutlinedButton.icon(
                      key: const Key('recover-history'),
                      onPressed:
                          busy ||
                              status?.historicalRecoveryState !=
                                  HistoricalRecoveryState.available
                          ? null
                          : widget.controller.recoverHistoricalMessages,
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Recover encrypted history'),
                    ),
                  ),
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
                          enabled: !busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[],
                          decoration: const InputDecoration(
                            labelText: 'Recovery passphrase',
                          ),
                          onSubmitted: busy
                              ? null
                              : (_) => _restoreWithPassphrase(),
                        ),
                        const SizedBox(height: KiteSpacing.sm),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: const Key('restore-passphrase'),
                            onPressed: busy ? null : _restoreWithPassphrase,
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
                          onPressed: busy ? null : _selectRoomKeyBackup,
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
                          enabled: !busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[],
                          decoration: const InputDecoration(
                            labelText: 'Export passphrase',
                          ),
                          onSubmitted: busy
                              ? null
                              : (_) => _importRoomKeyBackup(),
                        ),
                        const SizedBox(height: KiteSpacing.sm),
                        FilledButton.icon(
                          key: const Key('import-room-key-backup'),
                          onPressed: busy ? null : _importRoomKeyBackup,
                          icon: const Icon(Icons.key_rounded),
                          label: const Text('Import room keys'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    key: const Key('encryption-recovery-status-slot'),
                    height: 72,
                    child: Padding(
                      padding: const EdgeInsets.only(top: KiteSpacing.md),
                      child: Semantics(
                        liveRegion: true,
                        child: AnimatedSwitcher(
                          duration: KiteMotion.resolve(
                            context,
                            KiteMotion.standard,
                          ),
                          child: Text(
                            error ??
                                (importResult == null
                                    ? ''
                                    : 'Imported ${importResult.importedCount} of ${importResult.totalCount} room keys.'),
                            key: const Key('encryption-recovery-error'),
                            style: KiteTypography.metadata.copyWith(
                              color: error == null
                                  ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecoveryOverview extends StatelessWidget {
  const _RecoveryOverview({required this.status});

  final EncryptionRecoveryStatus? status;

  @override
  Widget build(BuildContext context) {
    final backupReady = status?.backupState == EncryptedBackupState.ready;
    final needsRecovery =
        status?.backupState == EncryptedBackupState.needsRecovery;
    final colors = Theme.of(context).colorScheme;
    final icon = backupReady
        ? Icons.verified_user_rounded
        : needsRecovery
        ? Icons.warning_amber_rounded
        : Icons.shield_outlined;
    final title = backupReady
        ? 'Recovery is set up'
        : needsRecovery
        ? 'Recovery needs attention'
        : 'Check your recovery setup';
    final detail = backupReady
        ? 'Encrypted backup is available for this account.'
        : needsRecovery
        ? 'Restore your encryption keys to read older encrypted messages.'
        : 'Kite is checking the Matrix backup and session state.';

    return Container(
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
    return Card(
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
