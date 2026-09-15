import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/authentication_screen.dart';

final class _FakeAuthenticationGateway implements AuthenticationGateway {
  HomeserverLoginMethods? discoveryResult;
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
    return AuthenticatedSession(
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
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(
      gateway.discoveredHomeserver?.uri,
      Uri.parse('https://matrix.example.org'),
    );
    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('username-field')), ' alice ');
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pumpAndSettle();

    expect(gateway.username, 'alice');
    expect(gateway.password, 'correct horse battery staple');
    expect(gateway.passwordHomeserver?.uri.host, 'matrix.example.org');
    expect(authenticated?.userId, '@alice:matrix.example.org');
    expect(find.text('correct horse battery staple'), findsNothing);
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);
  });

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
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('registration-available')));
    expect(requestedHomeserver?.uri, homeserver.uri);
  });

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
