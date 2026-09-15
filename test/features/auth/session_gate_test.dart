import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/session_gate.dart';
import 'package:kite/features/auth/session_lifecycle.dart';

final class _SessionGateway implements SessionLifecycleGateway {
  _SessionGateway(this.restored);

  AuthenticatedSession? restored;
  AuthenticatedSession? persisted;

  @override
  Future<void> clear() async {}

  @override
  Future<void> logout(AuthenticatedSession session) async {}

  @override
  Future<void> persist(AuthenticatedSession session) async {
    persisted = session;
  }

  @override
  Future<AuthenticatedSession?> restore() async => restored;
}

final class _AuthenticationGateway implements AuthenticationGateway {
  _AuthenticationGateway({
    this.registrationAvailable = false,
    this.returnedUserId,
  });

  final bool registrationAvailable;
  final String? returnedUserId;

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async =>
      HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{AuthenticationMethod.password},
        registrationAvailable: registrationAvailable,
      );

  AuthenticatedSession _session(HomeserverAddress homeserver) =>
      AuthenticatedSession(
        userId: returnedUserId ?? '@alice:${homeserver.uri.host}',
        deviceId: 'DEVICE',
        homeserver: homeserver,
      );

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) async =>
      _session(HomeserverAddress.parse('matrix.example.org'));

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);
}

final class _RegistrationGateway implements AccountRegistrationGateway {
  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) async =>
      const RegistrationCredentialsStep();

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async => RegistrationCompleteStep(
    AuthenticatedSession(
      userId: '@${username.trim()}:${homeserver.uri.host}',
      deviceId: 'REGISTERED_DEVICE',
      homeserver: homeserver,
    ),
  );

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) async => throw StateError('Interactive authentication not requested.');
}

final class _VerificationGateway implements DeviceVerificationGateway {
  _VerificationGateway(this.trust, {this.trustFailure});

  CrossSigningTrustState trust;
  Object? trustFailure;
  int trustReads = 0;

  @override
  Future<void> cancelVerification(String transactionId) async {}

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() async {
    trustReads += 1;
    if (trustFailure case final error?) throw error;
    return trust;
  }

  @override
  Future<DeviceVerificationSession> startQrVerification() async =>
      DeviceVerificationSession(
        transactionId: 'stale-qr-transaction',
        method: DeviceVerificationMethod.qr,
        stage: DeviceVerificationStage.ready,
        qrCodeData: 'SDK-OWNED-QR-PAYLOAD',
      );

  @override
  Future<DeviceVerificationSession> startSasVerification() async =>
      throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async => throw UnimplementedError();
}

AuthenticatedSession _session() => AuthenticatedSession(
  userId: '@alice:matrix.example.org',
  deviceId: 'DEVICE',
  homeserver: HomeserverAddress.parse('matrix.example.org'),
);

void main() {
  testWidgets('restored session discards stale verification transaction', (
    tester,
  ) async {
    final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
    final verificationGateway = _VerificationGateway(
      CrossSigningTrustState.verified,
    );
    final verification = DeviceVerificationController(verificationGateway);
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);

    expect(await verification.startQrVerification(), isTrue);
    expect(verification.session.value, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(),
          verificationController: verification,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(verification.session.value, isNull);
    expect(verification.trustState.value, CrossSigningTrustState.verified);
    expect(verificationGateway.trustReads, 1);
    expect(find.text('Authenticated content'), findsOneWidget);
  });

  testWidgets('restored verified session reaches authenticated content', (
    tester,
  ) async {
    final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
    final verification = DeviceVerificationController(
      _VerificationGateway(CrossSigningTrustState.verified),
    );
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(),
          verificationController: verification,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Authenticated content'), findsOneWidget);
    expect(lifecycle.state.value, isA<SessionAuthenticated>());
    expect(verification.trustState.value, CrossSigningTrustState.verified);
  });

  testWidgets('restored unverified session is blocked by verification gate', (
    tester,
  ) async {
    final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
    final verification = DeviceVerificationController(
      _VerificationGateway(CrossSigningTrustState.unverified),
    );
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(),
          verificationController: verification,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mandatory-device-verification')),
      findsOneWidget,
    );
    expect(find.text('Authenticated content'), findsNothing);
    expect(find.text('Verification required'), findsOneWidget);
  });

  testWidgets(
    'verification lookup failure stays fail-closed without an endless spinner',
    (tester) async {
      final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
      final verification = DeviceVerificationController(
        _VerificationGateway(
          CrossSigningTrustState.unknown,
          trustFailure: StateError('access_token=secret'),
        ),
      );
      addTearDown(lifecycle.dispose);
      addTearDown(verification.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(
            lifecycleController: lifecycle,
            authenticationGateway: _AuthenticationGateway(),
            verificationController: verification,
            authenticatedBuilder: (context) =>
                const Scaffold(body: Text('Authenticated content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('verification-status-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('mandatory-device-verification')),
        findsOneWidget,
      );
      expect(find.text('Verification status unavailable'), findsOneWidget);
      expect(
        verification.errorMessage.value,
        'Kite could not read device verification status.',
      );
      expect(verification.errorMessage.value, isNot(contains('secret')));
      expect(find.text('Authenticated content'), findsNothing);
    },
  );

  testWidgets('registration completes through the signed-out session flow', (
    tester,
  ) async {
    final sessionGateway = _SessionGateway(null);
    final lifecycle = SessionLifecycleController(sessionGateway);
    final verification = DeviceVerificationController(
      _VerificationGateway(CrossSigningTrustState.verified),
    );
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(
            registrationAvailable: true,
          ),
          registrationGateway: _RegistrationGateway(),
          verificationController: verification,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('registration-available')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('registration-heading')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('registration-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('registration-password')),
      'registration-password',
    );
    await tester.tap(find.byKey(const Key('registration-submit-credentials')));
    await tester.pumpAndSettle();

    expect(find.text('Authenticated content'), findsOneWidget);
    expect(sessionGateway.persisted?.userId, '@alice:matrix.example.org');
    expect(sessionGateway.persisted?.deviceId, 'REGISTERED_DEVICE');
    expect(verification.trustState.value, CrossSigningTrustState.verified);
  });

  testWidgets('soft logout never resumes into a different Matrix account', (
    tester,
  ) async {
    final sessionGateway = _SessionGateway(_session());
    final lifecycle = SessionLifecycleController(sessionGateway);
    final verification = DeviceVerificationController(
      _VerificationGateway(CrossSigningTrustState.verified),
    );
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);
    await lifecycle.restore();
    lifecycle.markSoftLoggedOut();

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(
            returnedUserId: '@mallory:matrix.example.org',
          ),
          verificationController: verification,
          restoreOnInit: false,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'correct-password-for-wrong-account',
    );
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pumpAndSettle();

    expect(lifecycle.state.value, isA<SessionSoftLoggedOut>());
    expect(sessionGateway.persisted, isNull);
    expect(find.text('Authenticated content'), findsNothing);
    expect(
      find.text('Sign in as @alice:matrix.example.org to continue.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'soft-logout reauthentication discards the previous verification transaction',
    (tester) async {
      final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
      final verificationGateway = _VerificationGateway(
        CrossSigningTrustState.unverified,
      );
      final verification = DeviceVerificationController(verificationGateway);
      addTearDown(lifecycle.dispose);
      addTearDown(verification.dispose);
      await lifecycle.restore();
      await verification.loadTrust();
      expect(await verification.startQrVerification(), isTrue);
      expect(verification.session.value, isNotNull);
      lifecycle.markSoftLoggedOut();
      verificationGateway.trust = CrossSigningTrustState.verified;

      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(
            lifecycleController: lifecycle,
            authenticationGateway: _AuthenticationGateway(),
            verificationController: verification,
            restoreOnInit: false,
            authenticatedBuilder: (context) =>
                const Scaffold(body: Text('Authenticated content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(verification.session.value, isNull);
      expect(verification.trustState.value, CrossSigningTrustState.unknown);

      await tester.enterText(
        find.byKey(const Key('password-field')),
        'correct-password',
      );
      await tester.tap(find.byKey(const Key('password-login')));
      await tester.pumpAndSettle();

      expect(verification.session.value, isNull);
      expect(verification.trustState.value, CrossSigningTrustState.verified);
      expect(verificationGateway.trustReads, 2);
      expect(find.text('Authenticated content'), findsOneWidget);
    },
  );

  testWidgets('soft logout returns to authentication with explicit notice', (
    tester,
  ) async {
    final lifecycle = SessionLifecycleController(_SessionGateway(_session()));
    final verification = DeviceVerificationController(
      _VerificationGateway(CrossSigningTrustState.verified),
    );
    addTearDown(lifecycle.dispose);
    addTearDown(verification.dispose);
    await lifecycle.restore();
    lifecycle.markSoftLoggedOut();

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          lifecycleController: lifecycle,
          authenticationGateway: _AuthenticationGateway(),
          verificationController: verification,
          restoreOnInit: false,
          authenticatedBuilder: (context) =>
              const Scaffold(body: Text('Authenticated content')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('soft-logout-notice')), findsOneWidget);
    expect(
      find.text(
        'Your Matrix session expired. Sign in again with the same account.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('homeserver-field')), findsNothing);
    expect(find.byKey(const Key('change-homeserver')), findsNothing);
    final username = tester.widget<TextField>(
      find.byKey(const Key('username-field')),
    );
    expect(username.controller?.text, '@alice:matrix.example.org');
    expect(find.text('Authenticated content'), findsNothing);
  });
}
