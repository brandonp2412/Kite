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

  Future<void> clear();
}

final class SessionLifecycleController {
  SessionLifecycleController(this._gateway);

  final SessionLifecycleGateway _gateway;

  final state = signal<SessionLifecycleState>(const SessionSignedOut());
  final errorMessage = signal<String?>(null);

  bool get isRestoring => state.value is SessionRestoring;

  Future<void> restore() async {
    if (isRestoring) return;

    errorMessage.value = null;
    state.value = const SessionRestoring();
    try {
      final restored = await _gateway.restore();
      state.value = restored == null
          ? const SessionSignedOut()
          : SessionAuthenticated(restored);
    } catch (_) {
      state.value = const SessionSignedOut();
      errorMessage.value = 'Kite could not restore your previous session.';
    }
  }

  Future<void> acceptAuthenticatedSession(AuthenticatedSession session) async {
    errorMessage.value = null;
    try {
      await _gateway.persist(session);
      state.value = SessionAuthenticated(session);
    } catch (_) {
      state.value = const SessionSignedOut();
      errorMessage.value = 'Kite could not save your session securely.';
    }
  }

  void markSoftLoggedOut() {
    final current = state.value;
    if (current is! SessionAuthenticated) return;
    errorMessage.value = null;
    state.value = SessionSoftLoggedOut(current.session);
  }

  Future<void> resumeAfterSoftLogout(AuthenticatedSession session) async {
    final current = state.value;
    if (current is! SessionSoftLoggedOut) return;
    if (session.userId != current.session.userId ||
        session.homeserver.uri != current.session.homeserver.uri) {
      errorMessage.value = 'Sign in again with the same account to continue.';
      return;
    }
    await acceptAuthenticatedSession(session);
  }

  Future<void> signOut() async {
    errorMessage.value = null;
    try {
      await _gateway.clear();
      state.value = const SessionSignedOut();
    } catch (_) {
      errorMessage.value = 'Kite could not finish signing out securely.';
    }
  }

  void dispose() {
    state.dispose();
    errorMessage.dispose();
  }
}
