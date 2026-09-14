import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_lifecycle.dart';

final class _FakeSessionLifecycleGateway implements SessionLifecycleGateway {
  AuthenticatedSession? restored;
  Object? restoreError;
  Object? persistError;
  Object? clearError;
  Object? logoutError;
  AuthenticatedSession? persisted;
  int clearCalls = 0;
  int logoutCalls = 0;
  AuthenticatedSession? loggedOutSession;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    if (clearError case final error?) throw error;
    restored = null;
  }

  @override
  Future<void> logout(AuthenticatedSession session) async {
    logoutCalls += 1;
    loggedOutSession = session;
    if (logoutError case final error?) throw error;
  }

  @override
  Future<void> persist(AuthenticatedSession session) async {
    if (persistError case final error?) throw error;
    persisted = session;
    restored = session;
  }

  @override
  Future<AuthenticatedSession?> restore() async {
    if (restoreError case final error?) throw error;
    return restored;
  }
}

AuthenticatedSession _session({
  String userId = '@alice:matrix.example.org',
  String deviceId = 'DEVICE',
  String homeserver = 'matrix.example.org',
}) {
  return AuthenticatedSession(
    userId: userId,
    deviceId: deviceId,
    homeserver: HomeserverAddress.parse(homeserver),
  );
}

void main() {
  test(
    'restores a persisted session without exposing gateway failures',
    () async {
      final gateway = _FakeSessionLifecycleGateway()..restored = _session();
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);

      await controller.restore();

      final restored = controller.state.value;
      expect(restored, isA<SessionAuthenticated>());
      expect(
        (restored as SessionAuthenticated).session.userId,
        '@alice:matrix.example.org',
      );

      gateway.restoreError = StateError('access_token=secret');
      await controller.restore();

      expect(controller.state.value, isA<SessionSignedOut>());
      expect(
        controller.errorMessage.value,
        'Kite could not restore your previous session.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'soft logout only resumes the same Matrix account and homeserver',
    () async {
      final gateway = _FakeSessionLifecycleGateway();
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);
      final initial = _session();

      await controller.acceptAuthenticatedSession(initial);
      controller.markSoftLoggedOut();

      expect(controller.state.value, isA<SessionSoftLoggedOut>());

      await controller.resumeAfterSoftLogout(
        _session(userId: '@mallory:matrix.example.org'),
      );
      expect(controller.state.value, isA<SessionSoftLoggedOut>());
      expect(
        controller.errorMessage.value,
        'Sign in again with the same account to continue.',
      );

      final replacement = _session(deviceId: 'NEW_DEVICE');
      await controller.resumeAfterSoftLogout(replacement);
      expect(controller.state.value, isA<SessionAuthenticated>());
      expect(gateway.persisted?.deviceId, 'NEW_DEVICE');
    },
  );

  test(
    'sign out invalidates the Matrix session before clearing local state',
    () async {
      final gateway = _FakeSessionLifecycleGateway();
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);
      final session = _session();
      await controller.acceptAuthenticatedSession(session);

      await controller.signOut();

      expect(gateway.logoutCalls, 1);
      expect(gateway.loggedOutSession, same(session));
      expect(gateway.clearCalls, 1);
      expect(controller.state.value, isA<SessionSignedOut>());
    },
  );

  test(
    'remote logout failure keeps the local authenticated session intact',
    () async {
      final gateway = _FakeSessionLifecycleGateway()
        ..logoutError = StateError('access_token=secret');
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);
      await controller.acceptAuthenticatedSession(_session());

      await controller.signOut();

      expect(gateway.clearCalls, 0);
      expect(controller.state.value, isA<SessionAuthenticated>());
      expect(
        controller.errorMessage.value,
        'Kite could not sign out this Matrix session.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test('remote logout success drops runtime authentication even if local clear fails', () async {
    final gateway = _FakeSessionLifecycleGateway()
      ..clearError = StateError('encrypted store busy');
    final controller = SessionLifecycleController(gateway);
    addTearDown(controller.dispose);
    await controller.acceptAuthenticatedSession(_session());

    await controller.signOut();

    expect(gateway.logoutCalls, 1);
    expect(gateway.clearCalls, 1);
    expect(controller.state.value, isA<SessionSignedOut>());
    expect(
      controller.errorMessage.value,
      'Signed out, but Kite could not clear all local session data.',
    );
  });

  test(
    'soft-logged-out sessions clear locally without a redundant logout',
    () async {
      final gateway = _FakeSessionLifecycleGateway();
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);
      await controller.acceptAuthenticatedSession(_session());
      controller.markSoftLoggedOut();

      await controller.signOut();

      expect(gateway.logoutCalls, 0);
      expect(gateway.clearCalls, 1);
      expect(controller.state.value, isA<SessionSignedOut>());
    },
  );
}
