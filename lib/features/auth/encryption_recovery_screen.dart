import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:signals/signals_flutter.dart';

class EncryptionRecoveryScreen extends StatefulWidget {
  const EncryptionRecoveryScreen({
    required this.controller,
    this.loadOnInit = true,
    super.key,
  });

  final EncryptionRecoveryController controller;
  final bool loadOnInit;

  @override
  State<EncryptionRecoveryScreen> createState() =>
      _EncryptionRecoveryScreenState();
}

class _EncryptionRecoveryScreenState extends State<EncryptionRecoveryScreen> {
  late final TextEditingController _recoveryKeyController;
  late final TextEditingController _passphraseController;

  @override
  void initState() {
    super.initState();
    _recoveryKeyController = TextEditingController();
    _passphraseController = TextEditingController();
    if (widget.loadOnInit) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    _clearSecrets();
    _recoveryKeyController.dispose();
    _passphraseController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encryption recovery')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final status = widget.controller.status.value;
            final busy = widget.controller.isBusy.value;
            final error = widget.controller.errorMessage.value;

            return ListView(
              key: const Key('encryption-recovery-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                const _SectionTitle(label: 'Encrypted backup'),
                _StatusCard(status: status),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
                  child: FilledButton.tonalIcon(
                    key: const Key('create-encrypted-backup'),
                    onPressed: busy
                        ? null
                        : widget.controller.createEncryptedBackup,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Enable encrypted backup'),
                  ),
                ),
                const Divider(height: KiteSpacing.xl),
                const _SectionTitle(label: 'Restore access'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    KiteSpacing.md,
                    0,
                    KiteSpacing.md,
                    KiteSpacing.md,
                  ),
                  child: Text(
                    'Recovery secrets are passed directly to the Matrix SDK and are never stored by Kite.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
                  child: TextField(
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
                    ),
                    onSubmitted: busy ? null : (_) => _restoreWithRecoveryKey(),
                  ),
                ),
                const SizedBox(height: KiteSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
                  child: FilledButton(
                    key: const Key('restore-recovery-key'),
                    onPressed: busy ? null : _restoreWithRecoveryKey,
                    child: const Text('Restore with recovery key'),
                  ),
                ),
                const SizedBox(height: KiteSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
                  child: TextField(
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
                    onSubmitted: busy ? null : (_) => _restoreWithPassphrase(),
                  ),
                ),
                const SizedBox(height: KiteSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
                  child: OutlinedButton(
                    key: const Key('restore-passphrase'),
                    onPressed: busy ? null : _restoreWithPassphrase,
                    child: const Text('Restore with passphrase'),
                  ),
                ),
                const Divider(height: KiteSpacing.xl),
                const _SectionTitle(label: 'Message history'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.md,
                  ),
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
                SizedBox(
                  key: const Key('encryption-recovery-status-slot'),
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
                          key: const Key('encryption-recovery-error'),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final EncryptionRecoveryStatus? status;

  @override
  Widget build(BuildContext context) {
    final backupLabel = switch (status?.backupState) {
      EncryptedBackupState.unavailable => 'Backup unavailable',
      EncryptedBackupState.ready => 'Backup ready',
      EncryptedBackupState.needsRecovery => 'Recovery required',
      EncryptedBackupState.unknown || null => 'Checking backup status',
    };
    final historyLabel = switch (status?.historicalRecoveryState) {
      HistoricalRecoveryState.available => 'History recovery available',
      HistoricalRecoveryState.recovering => 'Recovering encrypted history',
      HistoricalRecoveryState.complete => 'Encrypted history recovered',
      HistoricalRecoveryState.idle || null => 'History recovery idle',
    };

    return Container(
      key: const Key('encryption-recovery-summary'),
      margin: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        0,
        KiteSpacing.md,
        KiteSpacing.md,
      ),
      padding: const EdgeInsets.all(KiteSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(KiteRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(backupLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KiteSpacing.xs),
          Text(historyLabel),
          const SizedBox(height: KiteSpacing.xs),
          Text(
            status?.hasUnverifiedSessions == true
                ? 'Some sessions are not verified.'
                : 'No unverified sessions reported.',
          ),
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
