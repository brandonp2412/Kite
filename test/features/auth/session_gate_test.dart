import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async =>
      HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{AuthenticationMethod.password},
      );

  AuthenticatedSession _session(HomeserverAddress homeserver) =>
      AuthenticatedSession(
        userId: '@alice:${homeserver.uri.host}',
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

final class _VerificationGateway implements DeviceVerificationGateway {
  _VerificationGateway(this.trust);

  CrossSigningTrustState trust;

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
  Future<CrossSigningTrustState> loadCrossSigningTrust() async => trust;

  @override
  Future<DeviceVerificationSession> startQrVerification() async =>
      throw UnimplementedError();

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

    expect(find.byKey(const Key('soft-logout-notice')), findsOneWidget);
    expect(
      find.text(
        'Your Matrix session expired. Sign in again with the same account.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('homeserver-field')), findsOneWidget);
    expect(find.text('Authenticated content'), findsNothing);
  });
}
