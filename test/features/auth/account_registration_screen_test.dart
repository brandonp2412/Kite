import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/account_registration_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

final class _ScreenRegistrationGateway implements AccountRegistrationGateway {
  _ScreenRegistrationGateway(this.homeserver);

  final HomeserverAddress homeserver;
  String? username;
  String? password;
  int interactiveCalls = 0;

  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) async =>
      const RegistrationCredentialsStep();

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async {
    this.username = username;
    this.password = password;
    return const RegistrationInteractiveStep(
      publicInstructions: 'Confirm the homeserver challenge to continue.',
    );
  }

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) async {
    interactiveCalls += 1;
    return RegistrationCompleteStep(
      AuthenticatedSession(
        userId: '@alice:${homeserver.uri.host}',
        deviceId: 'DEVICE',
        homeserver: homeserver,
      ),
    );
  }
}

void main() {
  testWidgets('registration clears the password before interactive auth', (
    tester,
  ) async {
    final homeserver = HomeserverAddress.parse('matrix.example.org');
    final gateway = _ScreenRegistrationGateway(homeserver);
    AuthenticatedSession? authenticated;

    await tester.pumpWidget(
      MaterialApp(
        home: AccountRegistrationScreen(
          homeserver: homeserver,
          gateway: gateway,
          onAuthenticated: (session) => authenticated = session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('registration-username')),
      ' alice ',
    );
    await tester.enterText(
      find.byKey(const Key('registration-password')),
      'registration-password',
    );
    await tester.tap(find.byKey(const Key('registration-submit-credentials')));
    await tester.pumpAndSettle();

    expect(gateway.username, 'alice');
    expect(gateway.password, 'registration-password');
    expect(find.text('registration-password'), findsNothing);
    expect(
      find.byKey(const Key('registration-continue-interactive')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('registration-continue-interactive')),
    );
    await tester.pumpAndSettle();

    expect(gateway.interactiveCalls, 1);
    expect(authenticated?.userId, '@alice:matrix.example.org');
    expect(find.byKey(const Key('registration-complete')), findsOneWidget);
  });
}
