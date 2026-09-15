import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:signals/signals_flutter.dart';

class PrivacySecuritySettingsScreen extends StatefulWidget {
  const PrivacySecuritySettingsScreen({
    required this.verificationController,
    required this.recoveryController,
    required this.sessionDeviceController,
    required this.onOpenVerification,
    required this.onOpenRecovery,
    required this.onOpenSessions,
    this.onOpenAppLock,
    this.appLockEnabled,
    this.loadOnInit = true,
    super.key,
  });

  final DeviceVerificationController verificationController;
  final EncryptionRecoveryController recoveryController;
  final SessionDeviceController sessionDeviceController;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenRecovery;
  final VoidCallback onOpenSessions;
  final VoidCallback? onOpenAppLock;
  final bool? appLockEnabled;
  final bool loadOnInit;

  @override
  State<PrivacySecuritySettingsScreen> createState() =>
      _PrivacySecuritySettingsScreenState();
}

class _PrivacySecuritySettingsScreenState
    extends State<PrivacySecuritySettingsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      unawaited(widget.verificationController.loadTrust());
      unawaited(widget.recoveryController.refresh());
      unawaited(widget.sessionDeviceController.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & security')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final trust = widget.verificationController.trustState.value;
            final recovery = widget.recoveryController.status.value;
            final devices = widget.sessionDeviceController.devices.value;
            final loading =
                widget.verificationController.isBusy.value ||
                widget.recoveryController.isBusy.value ||
                widget.sessionDeviceController.isLoading.value;
            final unverifiedDevices = devices
                .where(
                  (device) =>
                      device.verification ==
                      SessionDeviceVerification.unverified,
                )
                .length;
            final error =
                widget.verificationController.errorMessage.value ??
                widget.recoveryController.errorMessage.value ??
                widget.sessionDeviceController.errorMessage.value;

            return ListView(
              key: const Key('privacy-security-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('privacy-security-loading-slot'),
                  height: 4,
                  child: loading ? const LinearProgressIndicator() : null,
                ),
                const _SectionTitle(label: 'Encryption'),
                ListTile(
                  key: const Key('privacy-security-verification'),
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Device verification'),
                  subtitle: Text(_verificationSubtitle(trust)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenVerification,
                ),
                ListTile(
                  key: const Key('privacy-security-recovery'),
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Encryption recovery'),
                  subtitle: Text(_recoverySubtitle(recovery)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenRecovery,
                ),
                const Divider(height: 1),
                const _SectionTitle(label: 'Sessions'),
                ListTile(
                  key: const Key('privacy-security-sessions'),
                  leading: const Icon(Icons.devices_other_outlined),
                  title: const Text('Signed-in devices'),
                  subtitle: Text(
                    devices.isEmpty
                        ? 'No device information loaded'
                        : unverifiedDevices == 0
                        ? '${devices.length} devices · all verified or unknown'
                        : '${devices.length} devices · $unverifiedDevices unverified',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenSessions,
                ),
                if (widget.onOpenAppLock != null) ...<Widget>[
                  const Divider(height: 1),
                  const _SectionTitle(label: 'App protection'),
                  ListTile(
                    key: const Key('privacy-security-app-lock'),
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('App lock'),
                    subtitle: Text(
                      widget.appLockEnabled == null
                          ? 'PIN and biometric protection'
                          : widget.appLockEnabled!
                          ? 'Enabled'
                          : 'Off',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenAppLock,
                  ),
                ],
                SizedBox(
                  key: const Key('privacy-security-status-slot'),
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

String _verificationSubtitle(CrossSigningTrustState trust) => switch (trust) {
  CrossSigningTrustState.verified => 'Verified with cross-signing',
  CrossSigningTrustState.unverified => 'Verification required',
  CrossSigningTrustState.unknown => 'Verification status unknown',
};

String _recoverySubtitle(EncryptionRecoveryStatus? status) {
  if (status == null) return 'Recovery status unknown';
  if (status.needsRecoveryAttention) return 'Recovery needs attention';
  return switch (status.backupState) {
    EncryptedBackupState.ready => 'Encrypted backup ready',
    EncryptedBackupState.unavailable => 'Encrypted backup unavailable',
    EncryptedBackupState.needsRecovery => 'Recovery required',
    EncryptedBackupState.unknown => 'Recovery status unknown',
  };
}
