import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/authentication_screen.dart';

final class _FakeAuthenticationGateway implements AuthenticationGateway {
  HomeserverLoginMethods? discoveryResult;
  AuthenticatedSession? nextSession;
  Object? discoveryError;
  Object? passwordError;
  Object? oidcError;
  Object? ssoError;
  HomeserverAddress? discoveredHomeserver;
  HomeserverAddress? passwordHomeserver;
  String? username;
  String? password;
  String? qrCodeData;
  int oidcCalls = 0;
  int ssoCalls = 0;

  AuthenticatedSession _session(HomeserverAddress homeserver) {
    return nextSession ??
        AuthenticatedSession(
          userId: '@alice:${homeserver.uri.host}',
          deviceId: 'DEVICE',
          homeserver: homeserver,
        );
  }

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async {
    discoveredHomeserver = homeserver;
    if (discoveryError case final error?) throw error;
    return discoveryResult ??
        HomeserverLoginMethods(
          homeserver: homeserver,
          methods: const <AuthenticationMethod>{AuthenticationMethod.password},
        );
  }

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async {
    passwordHomeserver = homeserver;
    this.username = username;
    this.password = password;
    if (passwordError case final error?) throw error;
    return _session(homeserver);
  }

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) async {
    oidcCalls += 1;
    if (oidcError case final error?) throw error;
    return _session(homeserver);
  }

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) async {
    ssoCalls += 1;
    if (ssoError case final error?) throw error;
    return _session(homeserver);
  }

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) async {
    this.qrCodeData = qrCodeData;
    return _session(HomeserverAddress.parse('matrix.example.org'));
  }
}

final class _FakeRegistrationGateway implements AccountRegistrationGateway {
  int beginCalls = 0;

  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) async {
    beginCalls += 1;
    return RegistrationCompleteStep(
      AuthenticatedSession(
        userId: '@new:${homeserver.uri.host}',
        deviceId: 'NEW_DEVICE',
        homeserver: homeserver,
      ),
    );
  }

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

Widget _app(_FakeAuthenticationGateway gateway) {
  return MaterialApp(home: AuthenticationScreen(gateway: gateway));
}

void main() {
  test('homeserver parsing defaults to HTTPS and rejects unsafe input', () {
    expect(
      HomeserverAddress.parse(' matrix.example.org ').uri,
      Uri.parse('https://matrix.example.org'),
    );
    expect(
      () => HomeserverAddress.parse('http://matrix.example.org'),
      throwsA(isA<AuthenticationInputException>()),
    );
    expect(
      () => HomeserverAddress.parse('https://user:secret@matrix.example.org'),
      throwsA(isA<AuthenticationInputException>()),
    );
    expect(
      () =>
          HomeserverAddress.parse('https://matrix.example.org?access_token=x'),
      throwsA(isA<AuthenticationInputException>()),
    );
  });

  testWidgets('homeserver continue requires a valid HTTPS address', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();

    await tester.pumpWidget(_app(gateway));

    FilledButton continueButton() => tester.widget<FilledButton>(
      find.byKey(const Key('discover-homeserver')),
    );

    expect(continueButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'http://matrix.example.org',
    );
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);
  });

  testWidgets('discovers supported methods and signs in with password', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();
    AuthenticatedSession? authenticated;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationScreen(
          gateway: gateway,
          onAuthenticated: (session) => authenticated = session,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(
      gateway.discoveredHomeserver?.uri,
      Uri.parse('https://matrix.example.org'),
    );
    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsOneWidget);
    final usernameEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('username-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(usernameEditable.focusNode.hasFocus, isTrue);

    await tester.enterText(find.byKey(const Key('username-field')), ' alice ');
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'correct horse battery staple',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pumpAndSettle();

    expect(gateway.username, 'alice');
    expect(gateway.password, 'correct horse battery staple');
    expect(gateway.passwordHomeserver?.uri.host, 'matrix.example.org');
    expect(authenticated?.userId, '@alice:matrix.example.org');
    expect(find.text('correct horse battery staple'), findsNothing);
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);
  });

  testWidgets('password sign-in requires both credential fields', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    FilledButton signInButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('password-login')));

    expect(signInButton().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('username-field')), 'alice');
    await tester.pump();
    expect(signInButton().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
    expect(signInButton().onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('username-field')), '');
    await tester.pump();
    expect(signInButton().onPressed, isNull);
  });

  testWidgets('rejected password login clears the credential field', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway()
      ..passwordError = const AuthenticationRejectedException(
        'Incorrect username or password.',
      );

    await tester.pumpWidget(
      MaterialApp(home: AuthenticationScreen(gateway: gateway)),
    );
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username-field')), 'alice');
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'credential-that-must-not-linger',
    );

    await tester.pump();
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pumpAndSettle();

    expect(gateway.password, 'credential-that-must-not-linger');
    final passwordField = tester.widget<TextField>(
      find.byKey(const Key('password-field')),
    );
    expect(passwordField.controller?.text, isEmpty);
    expect(find.text('credential-that-must-not-linger'), findsNothing);
    expect(find.text('Incorrect username or password.'), findsOneWidget);
  });

  testWidgets('editing credentials clears a stale sign-in error', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway()
      ..passwordError = const AuthenticationRejectedException(
        'Incorrect username or password.',
      );

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username-field')), 'alice');
    await tester.enterText(find.byKey(const Key('password-field')), 'wrong');
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect username or password.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('username-field')), 'alice2');
    await tester.pump();

    expect(find.text('Incorrect username or password.'), findsNothing);
  });

  testWidgets('system back returns from credentials to homeserver selection', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('username-field')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homeserver-field')), findsOneWidget);
    expect(find.byKey(const Key('username-field')), findsNothing);
  });

  testWidgets('changing homeserver clears entered account credentials', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();
    await tester.pumpWidget(
      MaterialApp(home: AuthenticationScreen(gateway: gateway)),
    );

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username-field')), 'alice');
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'must-not-cross-homeservers',
    );

    await tester.tap(find.byKey(const Key('change-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'other.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('username-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('password-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.textContaining('must-not-cross-homeservers'), findsNothing);
  });

  testWidgets(
    'soft-logout context rediscovers and locks the expected account',
    (tester) async {
      final gateway = _FakeAuthenticationGateway();
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      gateway.discoveryResult = HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{AuthenticationMethod.password},
        registrationAvailable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            gateway: gateway,
            initialHomeserver: homeserver,
            expectedUserId: '@alice:matrix.example.org',
            lockHomeserver: true,
            registrationGateway: _FakeRegistrationGateway(),
            scanQrCode: () async => 'OTHER-DEVICE-LOGIN',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.discoveredHomeserver?.uri, homeserver.uri);
      expect(find.byKey(const Key('homeserver-field')), findsNothing);
      expect(find.byKey(const Key('change-homeserver')), findsNothing);
      expect(
        find.text(
          'Sign back in as @alice:matrix.example.org on matrix.example.org.',
        ),
        findsOneWidget,
      );
      final username = tester.widget<TextField>(
        find.byKey(const Key('username-field')),
      );
      expect(username.controller?.text, '@alice:matrix.example.org');
      expect(username.enabled, isFalse);
      final passwordEditable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('password-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(passwordEditable.focusNode.hasFocus, isTrue);
      expect(find.byKey(const Key('qr-device-login')), findsNothing);
      expect(find.byKey(const Key('registration-available')), findsNothing);
    },
  );

  testWidgets(
    'soft logout refuses a successful session for a different Matrix account',
    (tester) async {
      final gateway = _FakeAuthenticationGateway();
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      gateway.discoveryResult = HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{AuthenticationMethod.password},
      );
      gateway.nextSession = AuthenticatedSession(
        userId: '@mallory:matrix.example.org',
        deviceId: 'OTHER_DEVICE',
        homeserver: homeserver,
      );
      AuthenticatedSession? authenticated;

      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            gateway: gateway,
            initialHomeserver: homeserver,
            expectedUserId: '@alice:matrix.example.org',
            lockHomeserver: true,
            onAuthenticated: (session) => authenticated = session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'credential-that-must-not-switch-accounts',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('password-login')));
      await tester.pumpAndSettle();

      expect(authenticated, isNull);
      expect(
        find.text('Sign in as @alice:matrix.example.org to continue.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('password-field')))
            .controller
            ?.text,
        isEmpty,
      );
    },
  );

  testWidgets('only renders authentication methods advertised by discovery', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();
    final homeserver = HomeserverAddress.parse('matrix.example.org');
    gateway.discoveryResult = HomeserverLoginMethods(
      homeserver: homeserver,
      methods: const <AuthenticationMethod>{
        AuthenticationMethod.oidc,
        AuthenticationMethod.sso,
      },
      registrationAvailable: true,
    );

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-login')), findsNothing);
    expect(find.byKey(const Key('oidc-login')), findsOneWidget);
    expect(find.byKey(const Key('sso-login')), findsOneWidget);
    expect(find.byKey(const Key('registration-available')), findsOneWidget);

    await tester.tap(find.byKey(const Key('oidc-login')));
    await tester.pumpAndSettle();
    expect(gateway.oidcCalls, 1);
  });

  testWidgets('browser authentication clears an entered password first', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway()
      ..oidcError = const AuthenticationRejectedException(
        'Browser sign in was cancelled.',
      );
    final homeserver = HomeserverAddress.parse('matrix.example.org');
    gateway.discoveryResult = HomeserverLoginMethods(
      homeserver: homeserver,
      methods: const <AuthenticationMethod>{
        AuthenticationMethod.password,
        AuthenticationMethod.oidc,
        AuthenticationMethod.sso,
      },
    );

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'must-not-survive-browser-handoff',
    );

    await tester.tap(find.byKey(const Key('oidc-login')));
    await tester.pumpAndSettle();

    expect(gateway.oidcCalls, 1);
    expect(find.text('Browser sign in was cancelled.'), findsOneWidget);
    final passwordField = tester.widget<TextField>(
      find.byKey(const Key('password-field')),
    );
    expect(passwordField.controller?.text, isEmpty);
    expect(
      find.textContaining('must-not-survive-browser-handoff'),
      findsNothing,
    );
  });

  testWidgets('registration handoff uses the discovered homeserver', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway();
    final homeserver = HomeserverAddress.parse('matrix.example.org');
    gateway.discoveryResult = HomeserverLoginMethods(
      homeserver: homeserver,
      methods: const <AuthenticationMethod>{AuthenticationMethod.password},
      registrationAvailable: true,
    );
    HomeserverAddress? requestedHomeserver;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationScreen(
          gateway: gateway,
          onRegistrationRequested: (value) => requestedHomeserver = value,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('password-field')),
      'must-not-survive-registration-handoff',
    );
    expect(find.text('Create an account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('registration-available')));
    expect(requestedHomeserver?.uri, homeserver.uri);
    final passwordField = tester.widget<TextField>(
      find.byKey(const Key('password-field')),
    );
    expect(passwordField.controller?.text, isEmpty);
  });

  testWidgets(
    'built-in registration returns the authenticated Matrix session',
    (tester) async {
      final gateway = _FakeAuthenticationGateway();
      final registrationGateway = _FakeRegistrationGateway();
      final homeserver = HomeserverAddress.parse('matrix.example.org');
      gateway.discoveryResult = HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{AuthenticationMethod.password},
        registrationAvailable: true,
      );
      AuthenticatedSession? authenticated;

      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            gateway: gateway,
            registrationGateway: registrationGateway,
            onAuthenticated: (session) => authenticated = session,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('homeserver-field')),
        'matrix.example.org',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('discover-homeserver')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('registration-available')));
      await tester.pumpAndSettle();

      expect(registrationGateway.beginCalls, 1);
      expect(authenticated?.userId, '@new:matrix.example.org');
      expect(find.byType(AuthenticationScreen), findsOneWidget);
    },
  );

  testWidgets(
    'device QR login passes opaque data to the gateway and clears it from UI',
    (tester) async {
      final gateway = _FakeAuthenticationGateway();
      AuthenticatedSession? authenticated;

      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            gateway: gateway,
            scanQrCode: () async => 'OPAQUE-DEVICE-LOGIN-PAYLOAD',
            onAuthenticated: (session) => authenticated = session,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('qr-device-login')));
      await tester.pumpAndSettle();

      expect(gateway.qrCodeData, 'OPAQUE-DEVICE-LOGIN-PAYLOAD');
      expect(authenticated?.userId, '@alice:matrix.example.org');
      expect(find.byKey(const Key('authenticated-session')), findsOneWidget);
      expect(find.textContaining('OPAQUE-DEVICE-LOGIN-PAYLOAD'), findsNothing);
    },
  );

  testWidgets('unexpected errors never expose gateway exception details', (
    tester,
  ) async {
    final gateway = _FakeAuthenticationGateway()
      ..discoveryError = StateError('access_token=super-secret');

    await tester.pumpWidget(_app(gateway));
    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(
      find.text('Kite could not connect to that homeserver.'),
      findsOneWidget,
    );
    expect(find.textContaining('super-secret'), findsNothing);
    expect(find.textContaining('access_token'), findsNothing);
  });
}
