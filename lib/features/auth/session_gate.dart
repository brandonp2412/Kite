import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/authentication_screen.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/device_verification_screen.dart';
import 'package:kite/features/auth/session_lifecycle.dart';
import 'package:signals/signals_flutter.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({
    required this.lifecycleController,
    required this.authenticationGateway,
    required this.verificationController,
    required this.authenticatedBuilder,
    this.registrationGateway,
    this.scanLoginQrCode,
    this.scanVerificationQrCode,
    this.verificationQrBuilder,
    this.restoreOnInit = true,
    super.key,
  });

  final SessionLifecycleController lifecycleController;
  final AuthenticationGateway authenticationGateway;
  final DeviceVerificationController verificationController;
  final WidgetBuilder authenticatedBuilder;
  final AccountRegistrationGateway? registrationGateway;
  final AuthenticationQrScanner? scanLoginQrCode;
  final VerificationQrScanner? scanVerificationQrCode;
  final VerificationQrBuilder? verificationQrBuilder;
  final bool restoreOnInit;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  var _authenticationGeneration = 0;
  late final void Function() _disposeLifecycleEffect;

  @override
  void initState() {
    super.initState();
    _disposeLifecycleEffect = effect(() {
      final lifecycleState = widget.lifecycleController.state.value;
      if (lifecycleState is! SessionAuthenticated) {
        widget.verificationController.resetForAccountChange();
      }
    });
    if (widget.restoreOnInit) {
      unawaited(_restore());
    }
  }

  @override
  void dispose() {
    _disposeLifecycleEffect();
    super.dispose();
  }

  Future<void> _restore() async {
    await widget.lifecycleController.restore();
    if (!mounted) return;
    if (widget.lifecycleController.state.value is SessionAuthenticated) {
      await _refreshVerificationForAuthenticatedSession();
    }
  }

  Future<void> _authenticated(AuthenticatedSession session) async {
    final before = widget.lifecycleController.state.value;
    if (before is SessionSoftLoggedOut) {
      await widget.lifecycleController.resumeAfterSoftLogout(session);
    } else {
      await widget.lifecycleController.acceptAuthenticatedSession(session);
    }
    if (!mounted) return;

    if (widget.lifecycleController.state.value is SessionAuthenticated) {
      await _refreshVerificationForAuthenticatedSession();
      return;
    }

    setState(() => _authenticationGeneration += 1);
  }

  Future<void> _refreshVerificationForAuthenticatedSession() async {
    widget.verificationController.resetForAccountChange();
    await widget.verificationController.loadTrust();
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final lifecycleState = widget.lifecycleController.state.value;
        final lifecycleError = widget.lifecycleController.errorMessage.value;
        final verificationTrust =
            widget.verificationController.trustState.value;
        final verificationBusy = widget.verificationController.isBusy.value;
        final verificationError =
            widget.verificationController.errorMessage.value;

        if (lifecycleState is SessionRestoring) {
          return const _SessionProgress(
            key: Key('session-restoring'),
            label: 'Restoring your session…',
          );
        }

        if (lifecycleState is SessionSignedOut ||
            lifecycleState is SessionSoftLoggedOut) {
          final softLogout = lifecycleState is SessionSoftLoggedOut
              ? lifecycleState
              : null;
          return Stack(
            children: <Widget>[
              AuthenticationScreen(
                key: ValueKey<int>(_authenticationGeneration),
                gateway: widget.authenticationGateway,
                scanQrCode: widget.scanLoginQrCode,
                registrationGateway: widget.registrationGateway,
                onAuthenticated: _authenticated,
                initialHomeserver: softLogout?.session.homeserver,
                expectedUserId: softLogout?.session.userId,
                lockHomeserver: softLogout != null,
              ),
              if (lifecycleState is SessionSoftLoggedOut)
                const Positioned(
                  left: KiteSpacing.md,
                  right: KiteSpacing.md,
                  top: KiteSpacing.md,
                  child: SafeArea(
                    child: _SessionNotice(
                      key: Key('soft-logout-notice'),
                      text: 'Your Matrix session expired. Sign in again with the same account.',
                    ),
                  ),
                ),
              if (lifecycleError != null)
                Positioned(
                  left: KiteSpacing.md,
                  right: KiteSpacing.md,
                  bottom: KiteSpacing.md,
                  child: SafeArea(
                    top: false,
                    child: _SessionNotice(
                      key: const Key('session-error-notice'),
                      text: lifecycleError,
                      isError: true,
                    ),
                  ),
                ),
            ],
          );
        }

        if (lifecycleState is SessionAuthenticated) {
          if (verificationBusy ||
              (verificationTrust == CrossSigningTrustState.unknown &&
                  verificationError == null)) {
            return const _SessionProgress(
              key: Key('verification-status-loading'),
              label: 'Checking device verification…',
            );
          }
          if (widget.verificationController.requiresVerification) {
            return DeviceVerificationScreen(
              key: const Key('mandatory-device-verification'),
              controller: widget.verificationController,
              loadOnInit: false,
              scanQrCode: widget.scanVerificationQrCode,
              qrBuilder: widget.verificationQrBuilder,
            );
          }
          return widget.authenticatedBuilder(context);
        }

        return const _SessionProgress(label: 'Preparing Kite…');
      },
    );
  }
}

class _SessionProgress extends StatelessWidget {
  const _SessionProgress({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: KiteSpacing.md),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionNotice extends StatelessWidget {
  const _SessionNotice({required this.text, this.isError = false, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: isError ? colors.errorContainer : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(KiteRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KiteSpacing.md,
          vertical: KiteSpacing.sm,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: KiteTypography.metadata.copyWith(
            color: isError ? colors.onErrorContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
