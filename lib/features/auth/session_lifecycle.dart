import 'package:kite/core/async_controller_lifecycle.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals.dart';

sealed class SessionLifecycleState {
  const SessionLifecycleState();
}

final class SessionSignedOut extends SessionLifecycleState {
  const SessionSignedOut();
}

final class SessionRestoring extends SessionLifecycleState {
  const SessionRestoring();
}

final class SessionAuthenticated extends SessionLifecycleState {
  const SessionAuthenticated(this.session);

  final AuthenticatedSession session;
}

final class SessionSoftLoggedOut extends SessionLifecycleState {
  const SessionSoftLoggedOut(this.session);

  final AuthenticatedSession session;
}

abstract interface class SessionLifecycleGateway {
  Future<AuthenticatedSession?> restore();

  Future<void> persist(AuthenticatedSession session);

  Future<void> logout(AuthenticatedSession session);

  Future<void> clear();
}

final class SessionLifecycleController with AsyncControllerLifecycle {
  SessionLifecycleController(this._gateway);

  final SessionLifecycleGateway _gateway;
  Future<void> _operationTail = Future<void>.value();
  bool _restoreQueued = false;

  final state = signal<SessionLifecycleState>(const SessionSignedOut());
  final errorMessage = signal<String?>(null);

  bool get isRestoring => state.value is SessionRestoring;

  Future<void> restore() {
    if (controllerDisposed || isRestoring || _restoreQueued) {
      return Future<void>.value();
    }
    _restoreQueued = true;
    return _enqueue(() async {
      try {
        await _restore();
      } finally {
        _restoreQueued = false;
      }
    });
  }

  Future<void> _restore() async {
    if (controllerDisposed) return;
    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    state.value = const SessionRestoring();
    try {
      final restored = await _gateway.restore();
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      if (restored == null) {
        state.value = const SessionSignedOut();
        return;
      }
      if (!_isValidSession(restored)) {
        state.value = const SessionSignedOut();
        errorMessage.value = 'Kite could not restore your previous session.';
        try {
          await _gateway.clear();
        } catch (_) {}
        return;
      }
      state.value = SessionAuthenticated(restored);
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        state.value = const SessionSignedOut();
        errorMessage.value = 'Kite could not restore your previous session.';
      }
    }
  }

  Future<void> acceptAuthenticatedSession(AuthenticatedSession session) =>
      _enqueue(() => _acceptAuthenticatedSession(session));

  Future<void> _acceptAuthenticatedSession(AuthenticatedSession session) async {
    if (controllerDisposed) return;
    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    if (!_isValidSession(session)) {
      state.value = const SessionSignedOut();
      errorMessage.value = 'Kite received an invalid authentication session.';
      return;
    }
    try {
      await _gateway.persist(session);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      state.value = SessionAuthenticated(session);
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        state.value = const SessionSignedOut();
        errorMessage.value = 'Kite could not save your session securely.';
      }
    }
  }

  void markSoftLoggedOut() {
    if (controllerDisposed) return;
    final current = state.value;
    if (current is SessionAuthenticated) {
      errorMessage.value = null;
      state.value = SessionSoftLoggedOut(current.session);
    }
  }

  Future<void> resumeAfterSoftLogout(AuthenticatedSession session) =>
      _enqueue(() => _resumeAfterSoftLogout(session));

  Future<void> _resumeAfterSoftLogout(AuthenticatedSession session) async {
    if (controllerDisposed) return;
    final current = state.value;
    if (current is SessionSoftLoggedOut) {
      final sameAccount = session.userId == current.session.userId;
      final sameHomeserver =
          session.homeserver.uri == current.session.homeserver.uri;
      final sameDevice = session.deviceId == current.session.deviceId;
      if (sameAccount && sameHomeserver && sameDevice) {
        await _acceptAuthenticatedSession(session);
        return;
      }
      errorMessage.value =
          'Sign in again with the same account and device to continue.';
    }
  }

  Future<void> signOut() => _enqueue(_signOut);

  Future<void> _signOut() async {
    if (controllerDisposed) return;
    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    final current = state.value;

    var remoteLogoutFailed = false;
    if (current is SessionAuthenticated) {
      try {
        await _gateway.logout(current.session);
      } catch (_) {
        remoteLogoutFailed = true;
      }
    }

    try {
      await _gateway.clear();
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      state.value = const SessionSignedOut();
      if (remoteLogoutFailed) {
        errorMessage.value = 'Signed out from Kite, but the Matrix server may still list this device.';
      }
    } catch (_) {
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      if (current is SessionAuthenticated) {
        state.value = const SessionSignedOut();
        errorMessage.value = remoteLogoutFailed
            ? 'Kite hid the signed-in session, but could not confirm server sign-out or clear all local session data.'
            : 'Signed out, but Kite could not clear all local session data.';
      } else {
        errorMessage.value = 'Kite could not clear the local session securely.';
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (controllerDisposed) return Future<void>.value();
    final lifecycle = captureControllerLifecycle();
    final result = _operationTail.then((_) {
      if (!isControllerLifecycleCurrent(lifecycle)) return Future<void>.value();
      return operation();
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  bool _isValidSession(AuthenticatedSession session) {
    final userId = session.userId.trim();
    final deviceId = session.deviceId.trim();
    final separator = userId.indexOf(':');
    return userId == session.userId &&
        userId.startsWith('@') &&
        separator > 1 &&
        separator < userId.length - 1 &&
        !userId.contains(RegExp(r'\s')) &&
        deviceId.isNotEmpty &&
        deviceId == session.deviceId;
  }

  void dispose() {
    if (!disposeControllerLifecycle()) return;
    _restoreQueued = false;
    state.dispose();
    errorMessage.dispose();
  }
}
