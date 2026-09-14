import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/session_lifecycle.dart';

final class _FakeSessionLifecycleGateway implements SessionLifecycleGateway {
  AuthenticatedSession? restored;
  Object? restoreError;
  Object? persistError;
  Object? clearError;
  AuthenticatedSession? persisted;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    if (clearError case final error?) throw error;
    restored = null;
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
    'sign out clears persisted session before dropping local state',
    () async {
      final gateway = _FakeSessionLifecycleGateway();
      final controller = SessionLifecycleController(gateway);
      addTearDown(controller.dispose);
      await controller.acceptAuthenticatedSession(_session());

      gateway.clearError = StateError('store busy');
      await controller.signOut();
      expect(controller.state.value, isA<SessionAuthenticated>());
      expect(
        controller.errorMessage.value,
        'Kite could not finish signing out securely.',
      );

      gateway.clearError = null;
      await controller.signOut();
      expect(controller.state.value, isA<SessionSignedOut>());
      expect(gateway.clearCalls, 2);
    },
  );
}
