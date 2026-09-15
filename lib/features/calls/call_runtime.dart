import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kite/features/calls/call_session.dart';

final class KiteCallRuntimeCoordinator {
  KiteCallRuntimeCoordinator(this._call);

  final KiteCallCoordinator _call;
  String? _hydratedCallId;

  Future<void> hydrateActiveCall() async {
    if (!_isRunning) return;
    await _ensureContinuationCapabilities();
  }

  Future<bool> handleAppState(KiteCallAppState state) async {
    if (!_isRunning) return false;
    if (_call.appState.value == state) return true;

    final capabilities = await _ensureContinuationCapabilities();
    if (!capabilities.supports(state)) return false;

    await _call.setAppState(state);
    return true;
  }

  Future<bool> handleAudioInterruption(bool interrupted) async {
    if (!_isRunning) return false;
    await _call.setMediaInterrupted(interrupted);
    return true;
  }

  Future<bool> handleConnectivity(bool connected) async {
    if (!_isRunning) return false;

    if (!connected) {
      if (_call.phase.value == KiteCallPhase.active) {
        _call.markTransientNetworkLoss();
      }
      return _call.phase.value == KiteCallPhase.reconnecting;
    }

    if (_call.phase.value != KiteCallPhase.reconnecting) return true;
    await _call.reconnectAfterTransientNetworkLoss();
    return true;
  }

  Future<KiteCallContinuationCapabilities>
  _ensureContinuationCapabilities() async {
    final callId = _call.session.value?.callId;
    if (callId == null) return KiteCallContinuationCapabilities.none;
    if (_hydratedCallId == callId) {
      return _call.continuationCapabilities.value;
    }
    final capabilities = await _call.refreshContinuationCapabilities();
    _hydratedCallId = callId;
    return capabilities;
  }

  bool get _isRunning {
    final phase = _call.phase.value;
    return phase == KiteCallPhase.active || phase == KiteCallPhase.reconnecting;
  }
}

typedef KiteCallRuntimeErrorHandler = void Function(
  Object error,
  StackTrace stack,
);

final class KiteCallRuntimeBinding with WidgetsBindingObserver {
  KiteCallRuntimeBinding({
    required this.runtime,
    WidgetsBinding? binding,
    this.onError,
  }) : _binding = binding ?? WidgetsBinding.instance;

  final KiteCallRuntimeCoordinator runtime;
  final WidgetsBinding _binding;
  final KiteCallRuntimeErrorHandler? onError;
  bool _attached = false;

  bool get isAttached => _attached;

  Future<void> attach() async {
    if (_attached) return;
    _binding.addObserver(this);
    _attached = true;
    await runtime.hydrateActiveCall();
    final lifecycleState = _binding.lifecycleState;
    if (lifecycleState != null) {
      await handleLifecycleState(lifecycleState);
    }
  }

  Future<void> detach() async {
    if (!_attached) return;
    _binding.removeObserver(this);
    _attached = false;
  }

  Future<bool> handleLifecycleState(AppLifecycleState state) =>
      runtime.handleAppState(mapLifecycleState(state));

  Future<bool> handleDeviceLocked() =>
      runtime.handleAppState(KiteCallAppState.locked);

  Future<bool> handleAudioInterruption(bool interrupted) =>
      runtime.handleAudioInterruption(interrupted);

  Future<bool> handleConnectivity(bool connected) =>
      runtime.handleConnectivity(connected);

  static KiteCallAppState mapLifecycleState(AppLifecycleState state) {
    return switch (state) {
      AppLifecycleState.resumed => KiteCallAppState.foreground,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => KiteCallAppState.background,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _run(handleLifecycleState(state));
  }

  void _run(Future<Object?> future) {
    unawaited(
      future.catchError((Object error, StackTrace stack) {
        onError?.call(error, stack);
        return null;
      }),
    );
  }
}
