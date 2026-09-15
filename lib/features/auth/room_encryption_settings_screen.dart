import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:signals/signals_flutter.dart';

class RoomEncryptionTrustBanner extends StatelessWidget {
  const RoomEncryptionTrustBanner({required this.controller, super.key});

  final EncryptionTrustController controller;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final trust = controller.state.value;
        final warning = controller.warningMessage;
        final (icon, label, warningState) = switch (trust) {
          RoomEncryptionTrust(isEncrypted: false) => (
            Icons.lock_open_rounded,
            'This room is not encrypted.',
            true,
          ),
          RoomEncryptionTrust(
            isEncrypted: true,
            trustState: EncryptionTrustState.verified,
          ) =>
            (
              Icons.verified_user_rounded,
              'Encrypted · verified devices',
              false,
            ),
          RoomEncryptionTrust(isEncrypted: true) => (
            Icons.gpp_maybe_outlined,
            warning ?? 'Encrypted · trust status unknown',
            warning != null,
          ),
          null => (Icons.shield_outlined, 'Checking encryption trust…', false),
        };
        final colors = Theme.of(context).colorScheme;
        return Container(
          key: const Key('room-encryption-trust-banner'),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
          color: warningState ? colors.errorContainer : colors.surfaceContainer,
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: warningState
                    ? colors.onErrorContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: KiteSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KiteTypography.metadata.copyWith(
                    color: warningState
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RoomEncryptionSettingsScreen extends StatefulWidget {
  const RoomEncryptionSettingsScreen({
    required this.roomId,
    required this.controller,
    this.loadOnInit = true,
    super.key,
  });

  final String roomId;
  final EncryptionTrustController controller;
  final bool loadOnInit;

  @override
  State<RoomEncryptionSettingsScreen> createState() =>
      _RoomEncryptionSettingsScreenState();
}

class _RoomEncryptionSettingsScreenState
    extends State<RoomEncryptionSettingsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      unawaited(widget.controller.load(widget.roomId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encryption')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final trust = widget.controller.state.value;
            final busy = widget.controller.isBusy.value;
            final error = widget.controller.errorMessage.value;
            return ListView(
              key: const Key('room-encryption-settings-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('room-encryption-loading-slot'),
                  height: 4,
                  child: busy ? const LinearProgressIndicator() : null,
                ),
                RoomEncryptionTrustBanner(controller: widget.controller),
                const SizedBox(height: KiteSpacing.md),
                if (trust != null) ...<Widget>[
                  ListTile(
                    leading: Icon(
                      trust.isEncrypted
                          ? Icons.lock_outline_rounded
                          : Icons.lock_open_rounded,
                    ),
                    title: const Text('Room encryption'),
                    subtitle: Text(
                      trust.isEncrypted
                          ? 'Messages use Matrix end-to-end encryption.'
                          : 'Messages in this room are not end-to-end encrypted.',
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('encrypted-history-sharing'),
                    value: trust.historySharingEnabled,
                    onChanged:
                        busy ||
                            !trust.isEncrypted ||
                            !trust.historySharingSupported
                        ? null
                        : widget.controller.setHistorySharing,
                    secondary: const Icon(Icons.history_rounded),
                    title: const Text('Encrypted history sharing'),
                    subtitle: Text(
                      trust.historySharingSupported
                          ? 'Let supported Matrix clients share encrypted history according to room policy.'
                          : 'This homeserver or room does not support encrypted history sharing.',
                    ),
                  ),
                ],
                SizedBox(
                  key: const Key('room-encryption-status-slot'),
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
}
