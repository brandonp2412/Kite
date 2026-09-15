import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_unlock_screen.dart';
import 'package:signals/signals_flutter.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.controller,
    required this.child,
    this.refreshNotificationPrivacy,
    this.loadOnInit = true,
    super.key,
  });

  final AppLockController controller;
  final Widget child;
  final Future<void> Function()? refreshNotificationPrivacy;
  final bool loadOnInit;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late final void Function() _disposePrivacyEffect;
  bool? _lastNotificationPrivacy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _disposePrivacyEffect = effect(() {
      final hidden = widget.controller.shouldHideNotificationContents;
      final previous = _lastNotificationPrivacy;
      _lastNotificationPrivacy = hidden;
      if (previous != null && previous != hidden) {
        _refreshNotificationPrivacy();
      }
    });
    if (widget.loadOnInit) {
      unawaited(widget.controller.load());
    }
  }

  @override
  void dispose() {
    _disposePrivacyEffect();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }

    widget.controller.lock();
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final ready = widget.controller.isReady.value;
        final busy = widget.controller.isBusy.value;
        final locked = widget.controller.isLocked.value;
        final error = widget.controller.errorMessage.value;

        if (!ready) {
          return _ProtectedLoadingScreen(
            busy: busy,
            error: error,
            onRetry: busy ? null : widget.controller.load,
          );
        }

        if (locked) {
          return AppUnlockScreen(controller: widget.controller);
        }

        return widget.child;
      },
    );
  }

  void _refreshNotificationPrivacy() {
    final refresh = widget.refreshNotificationPrivacy;
    if (refresh == null) return;
    unawaited(_ignoreRefreshFailure(refresh));
  }

  Future<void> _ignoreRefreshFailure(Future<void> Function() refresh) async {
    try {
      await refresh();
    } catch (_) {}
  }
}

class _ProtectedLoadingScreen extends StatelessWidget {
  const _ProtectedLoadingScreen({
    required this.busy,
    required this.error,
    required this.onRetry,
  });

  final bool busy;
  final String? error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Kite is protected',
                    key: const Key('app-lock-protected-heading'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    key: const Key('app-lock-protected-status'),
                    height: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: busy
                          ? const Row(
                              children: <Widget>[
                                SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(child: Text('Checking app lock…')),
                              ],
                            )
                          : Text(
                              error ?? 'App lock state is unavailable.',
                              key: const Key('app-lock-protected-error'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: onRetry == null
                        ? const SizedBox.shrink()
                        : FilledButton(
                            key: const Key('app-lock-protected-retry'),
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
