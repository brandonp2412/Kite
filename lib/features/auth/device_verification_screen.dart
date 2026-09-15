import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:signals/signals_flutter.dart';

typedef VerificationQrScanner = Future<String?> Function();
typedef VerificationQrBuilder = Widget Function(
  BuildContext context,
  String opaquePayload,
);

class DeviceVerificationScreen extends StatefulWidget {
  const DeviceVerificationScreen({
    required this.controller,
    this.scanQrCode,
    this.qrBuilder,
    this.loadOnInit = true,
    super.key,
  });

  final DeviceVerificationController controller;
  final VerificationQrScanner? scanQrCode;
  final VerificationQrBuilder? qrBuilder;
  final bool loadOnInit;

  @override
  State<DeviceVerificationScreen> createState() =>
      _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      unawaited(widget.controller.loadTrust());
    }
  }

  Future<void> _scanQrCode() async {
    final scanner = widget.scanQrCode;
    if (scanner == null || widget.controller.isBusy.value) return;
    final payload = await scanner();
    if (!mounted || payload == null || payload.isEmpty) return;
    await widget.controller.submitScannedQrCode(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify this device')),
      body: SafeArea(
        top: false,
        child: SignalBuilder(
          builder: (context) {
            final trust = widget.controller.trustState.value;
            final session = widget.controller.session.value;
            final busy = widget.controller.isBusy.value;
            final error = widget.controller.errorMessage.value;

            return ListView(
              key: const Key('device-verification-list'),
              padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
              children: <Widget>[
                SizedBox(
                  key: const Key('verification-loading-slot'),
                  height: 4,
                  child: busy && session == null
                      ? const LinearProgressIndicator()
                      : null,
                ),
                _TrustSummary(trust: trust),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    KiteSpacing.md,
                    0,
                    KiteSpacing.md,
                    KiteSpacing.md,
                  ),
                  child: Text(
                    'Verification is performed by the Matrix SDK. Kite only presents SDK-provided QR or emoji comparisons.',
                  ),
                ),
                SizedBox(
                  key: const Key('verification-action-slot'),
                  height: 360,
                  child: AnimatedSwitcher(
                    duration: KiteMotion.resolve(context, KiteMotion.standard),
                    switchInCurve: KiteMotion.standardCurve,
                    switchOutCurve: KiteMotion.standardCurve,
                    child: _VerificationBody(
                      key: ValueKey<String>(
                        session == null
                            ? 'start'
                            : '${session.method.name}-${session.stage.name}',
                      ),
                      controller: widget.controller,
                      session: session,
                      busy: busy,
                      scanQrCode: widget.scanQrCode == null
                          ? null
                          : _scanQrCode,
                      qrBuilder: widget.qrBuilder,
                    ),
                  ),
                ),
                SizedBox(
                  key: const Key('verification-status-slot'),
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
                          key: const Key('verification-error'),
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

class _TrustSummary extends StatelessWidget {
  const _TrustSummary({required this.trust});

  final CrossSigningTrustState trust;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = switch (trust) {
      CrossSigningTrustState.verified => (
        Icons.verified_user_rounded,
        'Device verified',
        'Cross-signing reports this device as trusted.',
      ),
      CrossSigningTrustState.unverified => (
        Icons.gpp_maybe_outlined,
        'Verification required',
        'Compare with another trusted Matrix device to continue securely.',
      ),
      CrossSigningTrustState.unknown => (
        Icons.shield_outlined,
        'Checking verification',
        'Waiting for cross-signing trust state from the Matrix SDK.',
      ),
    };

    return Container(
      key: const Key('verification-trust-summary'),
      height: 132,
      margin: const EdgeInsets.all(KiteSpacing.md),
      padding: const EdgeInsets.all(KiteSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(KiteRadii.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 34),
          const SizedBox(width: KiteSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: KiteSpacing.xs),
                Text(detail, style: KiteTypography.metadata),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationBody extends StatelessWidget {
  const _VerificationBody({
    required this.controller,
    required this.session,
    required this.busy,
    required this.scanQrCode,
    required this.qrBuilder,
    super.key,
  });

  final DeviceVerificationController controller;
  final DeviceVerificationSession? session;
  final bool busy;
  final VoidCallback? scanQrCode;
  final VerificationQrBuilder? qrBuilder;

  @override
  Widget build(BuildContext context) {
    final current = session;
    if (current == null) {
      return _VerificationStart(
        busy: busy,
        scanQrCode: scanQrCode,
        onStartQr: controller.startQrVerification,
        onStartSas: controller.startSasVerification,
      );
    }

    if (current.stage == DeviceVerificationStage.verified) {
      return _TerminalVerificationState(
        icon: Icons.verified_rounded,
        title: 'Verification complete',
        detail: 'The Matrix SDK confirmed this verification.',
        actionLabel: 'Done',
        onAction: controller.clearCompletedSession,
      );
    }
    if (current.stage == DeviceVerificationStage.cancelled) {
      return _TerminalVerificationState(
        icon: Icons.cancel_outlined,
        title: 'Verification cancelled',
        detail: 'No trust change was applied.',
        actionLabel: 'Try again',
        onAction: controller.clearCompletedSession,
      );
    }

    return switch (current.method) {
      DeviceVerificationMethod.qr => _QrVerification(
        session: current,
        busy: busy,
        qrBuilder: qrBuilder,
        onConfirm: controller.confirmQrVerification,
        onCancel: controller.cancelVerification,
      ),
      DeviceVerificationMethod.sas => _SasVerification(
        session: current,
        busy: busy,
        onConfirm: controller.confirmSasVerification,
        onCancel: controller.cancelVerification,
      ),
    };
  }
}

class _VerificationStart extends StatelessWidget {
  const _VerificationStart({
    required this.busy,
    required this.scanQrCode,
    required this.onStartQr,
    required this.onStartSas,
  });

  final bool busy;
  final VoidCallback? scanQrCode;
  final Future<bool> Function() onStartQr;
  final Future<bool> Function() onStartSas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('start-qr-verification'),
            onPressed: busy ? null : onStartQr,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Show verification QR code'),
          ),
          const SizedBox(height: KiteSpacing.sm),
          if (scanQrCode != null) ...<Widget>[
            OutlinedButton.icon(
              key: const Key('scan-qr-verification'),
              onPressed: busy ? null : scanQrCode,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan verification QR code'),
            ),
            const SizedBox(height: KiteSpacing.sm),
          ],
          OutlinedButton.icon(
            key: const Key('start-sas-verification'),
            onPressed: busy ? null : onStartSas,
            icon: const Icon(Icons.emoji_emotions_outlined),
            label: const Text('Verify with emoji'),
          ),
        ],
      ),
    );
  }
}

class _QrVerification extends StatelessWidget {
  const _QrVerification({
    required this.session,
    required this.busy,
    required this.qrBuilder,
    required this.onConfirm,
    required this.onCancel,
  });

  final DeviceVerificationSession session;
  final bool busy;
  final VerificationQrBuilder? qrBuilder;
  final Future<bool> Function() onConfirm;
  final Future<bool> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final payload = session.qrCodeData;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            key: const Key('verification-qr-presentation'),
            width: 180,
            height: 180,
            child: payload != null && qrBuilder != null
                ? qrBuilder!(context, payload)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(KiteRadii.md),
                    ),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(KiteSpacing.md),
                        child: Text(
                          'QR presentation is handled by the platform verification adapter.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: KiteSpacing.md),
          Text(
            session.stage == DeviceVerificationStage.waitingForPeer
                ? 'The other device has responded. Confirm the match to finish.'
                : 'Use another trusted Matrix device to compare this verification.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KiteSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextButton(
                key: const Key('cancel-verification'),
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: KiteSpacing.sm),
              FilledButton(
                key: const Key('confirm-qr-verification'),
                onPressed: busy ? null : onConfirm,
                child: const Text('Confirm match'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SasVerification extends StatelessWidget {
  const _SasVerification({
    required this.session,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final DeviceVerificationSession session;
  final bool busy;
  final Future<bool> Function() onConfirm;
  final Future<bool> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text(
            'Confirm the same emoji appear on your other trusted device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KiteSpacing.lg),
          Wrap(
            key: const Key('sas-emoji'),
            alignment: WrapAlignment.center,
            spacing: KiteSpacing.md,
            runSpacing: KiteSpacing.sm,
            children: <Widget>[
              for (final emoji in session.sasEmoji)
                Text(emoji, style: const TextStyle(fontSize: 34)),
            ],
          ),
          const SizedBox(height: KiteSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextButton(
                key: const Key('cancel-verification'),
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: KiteSpacing.sm),
              FilledButton(
                key: const Key('confirm-sas-verification'),
                onPressed: busy || session.sasEmoji.isEmpty ? null : onConfirm,
                child: const Text('They match'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerminalVerificationState extends StatelessWidget {
  const _TerminalVerificationState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 48),
        const SizedBox(height: KiteSpacing.md),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: KiteSpacing.xs),
        Text(detail, textAlign: TextAlign.center),
        const SizedBox(height: KiteSpacing.md),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
