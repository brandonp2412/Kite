import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

final class _AuthenticationGateway implements AuthenticationGateway {
  AuthenticatedSession? nextSession;
  Object? failure;

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async {
    return HomeserverLoginMethods(
      homeserver: homeserver,
      methods: const <AuthenticationMethod>{
        AuthenticationMethod.password,
        AuthenticationMethod.oidc,
        AuthenticationMethod.sso,
      },
    );
  }

  AuthenticatedSession _session(HomeserverAddress homeserver) {
    return nextSession ??
        AuthenticatedSession(
          userId: '@alice:${homeserver.uri.host}',
          deviceId: 'DEVICE',
          homeserver: homeserver,
        );
  }

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async {
    if (failure case final error?) throw error;
    return _session(homeserver);
  }

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) async {
    return _session(HomeserverAddress.parse('matrix.example.org'));
  }

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);
}

void main() {
  test(
    'password authentication rejects a session for another homeserver',
    () async {
      final gateway = _AuthenticationGateway();
      final controller = AuthenticationController(gateway);
      addTearDown(controller.dispose);
      await controller.discover('matrix.example.org');
      gateway.nextSession = AuthenticatedSession(
        userId: '@alice:other.example.org',
        deviceId: 'DEVICE',
        homeserver: HomeserverAddress.parse('other.example.org'),
      );

      await controller.loginWithPassword(username: 'alice', password: 'secret');

      expect(controller.session.value, isNull);
      expect(
        controller.errorMessage.value,
        'Kite received an invalid authentication session.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'failed reauthentication cannot reuse a previously successful session',
    () async {
      final gateway = _AuthenticationGateway();
      final controller = AuthenticationController(gateway);
      addTearDown(controller.dispose);
      await controller.discover('matrix.example.org');

      await controller.loginWithPassword(username: 'alice', password: 'first');
      expect(controller.session.value, isNotNull);

      gateway.failure = StateError('access_token=secret');
      await controller.loginWithPassword(username: 'alice', password: 'second');

      expect(controller.session.value, isNull);
      expect(
        controller.errorMessage.value,
        'Sign in failed. Check your details and try again.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test('authentication rejects malformed Matrix identity metadata', () async {
    final gateway = _AuthenticationGateway()
      ..nextSession = AuthenticatedSession(
        userId: 'alice matrix.example.org',
        deviceId: '  ',
        homeserver: HomeserverAddress.parse('matrix.example.org'),
      );
    final controller = AuthenticationController(gateway);
    addTearDown(controller.dispose);

    await controller.loginWithQrCode('OPAQUE-QR-PAYLOAD');

    expect(controller.session.value, isNull);
    expect(
      controller.errorMessage.value,
      'Kite received an invalid authentication session.',
    );
    expect(controller.errorMessage.value, isNot(contains('OPAQUE-QR-PAYLOAD')));
  });

  test(
    'device QR login may securely hand off to a different homeserver',
    () async {
      final gateway = _AuthenticationGateway()
        ..nextSession = AuthenticatedSession(
          userId: '@alice:remote.example.org',
          deviceId: 'REMOTE_DEVICE',
          homeserver: HomeserverAddress.parse('remote.example.org'),
        );
      final controller = AuthenticationController(gateway);
      addTearDown(controller.dispose);

      await controller.loginWithQrCode('OPAQUE-QR-PAYLOAD');

      expect(controller.errorMessage.value, isNull);
      expect(controller.session.value?.userId, '@alice:remote.example.org');
      expect(controller.session.value?.deviceId, 'REMOTE_DEVICE');
    },
  );
}
