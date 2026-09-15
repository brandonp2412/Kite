import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

final class _FakeRegistrationGateway implements AccountRegistrationGateway {
  AccountRegistrationStep beginStep = const RegistrationCredentialsStep();
  AccountRegistrationStep? credentialsStep;
  AccountRegistrationStep? interactiveStep;
  Object? failure;
  HomeserverAddress? homeserver;
  String? username;
  String? password;
  int interactiveCalls = 0;

  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) async {
    this.homeserver = homeserver;
    if (failure case final error?) throw error;
    return beginStep;
  }

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) async {
    interactiveCalls += 1;
    if (failure case final error?) throw error;
    return interactiveStep ?? const RegistrationCredentialsStep();
  }

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async {
    this.homeserver = homeserver;
    this.username = username;
    this.password = password;
    if (failure case final error?) throw error;
    return credentialsStep ?? const RegistrationCredentialsStep();
  }
}

AuthenticatedSession _session(
  HomeserverAddress homeserver, {
  String deviceId = 'DEVICE',
}) => AuthenticatedSession(
  userId: '@alice:${homeserver.uri.host}',
  deviceId: deviceId,
  homeserver: homeserver,
);

void main() {
  test(
    'registration follows SDK-owned credentials and interactive steps',
    () async {
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      final gateway = _FakeRegistrationGateway()
        ..credentialsStep = const RegistrationInteractiveStep(
          publicInstructions: 'Confirm the server requirements to continue.',
        )
        ..interactiveStep = RegistrationCompleteStep(_session(homeserver));
      final controller = AccountRegistrationController(
        homeserver: homeserver,
        gateway: gateway,
      );
      addTearDown(controller.dispose);

      expect(await controller.begin(), isTrue);
      expect(controller.step.value, isA<RegistrationCredentialsStep>());

      expect(
        await controller.submitCredentials(
          username: ' alice ',
          password: 'correct horse battery staple',
        ),
        isTrue,
      );
      expect(gateway.username, 'alice');
      expect(gateway.password, 'correct horse battery staple');
      expect(controller.step.value, isA<RegistrationInteractiveStep>());

      expect(await controller.continueInteractiveAuthentication(), isTrue);
      expect(gateway.interactiveCalls, 1);
      expect(controller.step.value, isA<RegistrationCompleteStep>());
    },
  );

  test(
    'invalid completion cannot switch registration to another homeserver',
    () async {
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      final otherHomeserver = HomeserverAddress.parse('other.example.org');
      final gateway = _FakeRegistrationGateway()
        ..beginStep = RegistrationCompleteStep(_session(otherHomeserver));
      final controller = AccountRegistrationController(
        homeserver: homeserver,
        gateway: gateway,
      );
      addTearDown(controller.dispose);

      expect(await controller.begin(), isFalse);
      expect(controller.step.value, isNull);
      expect(
        controller.errorMessage.value,
        'Kite received an invalid registration state.',
      );

      gateway.beginStep = RegistrationCompleteStep(
        _session(homeserver, deviceId: ' DEVICE '),
      );
      expect(await controller.begin(), isFalse);
      expect(controller.step.value, isNull);
      expect(
        controller.errorMessage.value,
        'Kite received an invalid registration state.',
      );
    },
  );

  test(
    'unexpected failures never expose password or gateway details',
    () async {
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      final gateway = _FakeRegistrationGateway();
      final controller = AccountRegistrationController(
        homeserver: homeserver,
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      await controller.begin();
      gateway.failure = StateError('access_token=super-secret');

      expect(
        await controller.submitCredentials(
          username: 'alice',
          password: 'registration-password',
        ),
        isFalse,
      );
      expect(
        controller.errorMessage.value,
        'Kite could not create that account.',
      );
      expect(controller.errorMessage.value, isNot(contains('super-secret')));
      expect(
        controller.errorMessage.value,
        isNot(contains('registration-password')),
      );
    },
  );
}
