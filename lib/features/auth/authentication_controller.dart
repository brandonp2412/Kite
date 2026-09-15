import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals.dart';

enum AuthenticationProgress { idle, discovering, signingIn }

final class AuthenticationController {
  AuthenticationController(this._gateway);

  final AuthenticationGateway _gateway;

  final progress = signal(AuthenticationProgress.idle);
  final loginMethods = signal<HomeserverLoginMethods?>(null);
  final session = signal<AuthenticatedSession?>(null);
  final errorMessage = signal<String?>(null);

  bool get isBusy => progress.value != AuthenticationProgress.idle;

  Future<void> discover(String rawHomeserver) async {
    if (isBusy) return;

    errorMessage.value = null;
    HomeserverAddress homeserver;
    try {
      homeserver = HomeserverAddress.parse(rawHomeserver);
    } on AuthenticationInputException catch (error) {
      errorMessage.value = error.publicMessage;
      return;
    }

    loginMethods.value = null;
    session.value = null;
    progress.value = AuthenticationProgress.discovering;
    try {
      final discovered = await _gateway.discover(homeserver);
      if (discovered.homeserver.uri != homeserver.uri) {
        errorMessage.value = 'Kite received invalid homeserver discovery data.';
        return;
      }
      loginMethods.value = discovered;
    } on AuthenticationException catch (error) {
      errorMessage.value = error.publicMessage;
    } catch (_) {
      errorMessage.value = 'Kite could not connect to that homeserver.';
    } finally {
      progress.value = AuthenticationProgress.idle;
    }
  }

  Future<void> loginWithPassword({
    required String username,
    required String password,
  }) async {
    final methods = loginMethods.value;
    if (isBusy || methods == null) return;
    if (!methods.supports(AuthenticationMethod.password)) {
      errorMessage.value = 'This homeserver does not support password login.';
      return;
    }
    if (username.trim().isEmpty || password.isEmpty) {
      errorMessage.value = 'Enter your username and password.';
      return;
    }

    await _runSignIn(
      () => _gateway.loginWithPassword(
        homeserver: methods.homeserver,
        username: username.trim(),
        password: password,
      ),
      expectedHomeserver: methods.homeserver,
    );
  }

  Future<void> loginWithOidc() async {
    final methods = loginMethods.value;
    if (isBusy || methods == null) return;
    if (!methods.supports(AuthenticationMethod.oidc)) {
      errorMessage.value = 'This homeserver does not support OIDC login.';
      return;
    }
    await _runSignIn(
      () => _gateway.loginWithOidc(homeserver: methods.homeserver),
      expectedHomeserver: methods.homeserver,
    );
  }

  Future<void> loginWithSso() async {
    final methods = loginMethods.value;
    if (isBusy || methods == null) return;
    if (!methods.supports(AuthenticationMethod.sso)) {
      errorMessage.value = 'This homeserver does not support SSO login.';
      return;
    }
    await _runSignIn(
      () => _gateway.loginWithSso(homeserver: methods.homeserver),
      expectedHomeserver: methods.homeserver,
    );
  }

  Future<void> loginWithQrCode(String qrCodeData) async {
    if (isBusy) return;
    if (qrCodeData.trim().isEmpty) {
      errorMessage.value = 'Scan a valid Matrix sign-in QR code.';
      return;
    }
    await _runSignIn(() => _gateway.loginWithQrCode(qrCodeData));
  }

  Future<void> _runSignIn(
    Future<AuthenticatedSession> Function() action, {
    HomeserverAddress? expectedHomeserver,
  }) async {
    errorMessage.value = null;
    session.value = null;
    progress.value = AuthenticationProgress.signingIn;
    try {
      final authenticated = await action();
      if (!_isValidSession(
        authenticated,
        expectedHomeserver: expectedHomeserver,
      )) {
        session.value = null;
        errorMessage.value = 'Kite received an invalid authentication session.';
        return;
      }
      session.value = authenticated;
    } on AuthenticationException catch (error) {
      errorMessage.value = error.publicMessage;
    } catch (_) {
      errorMessage.value = 'Sign in failed. Check your details and try again.';
    } finally {
      progress.value = AuthenticationProgress.idle;
    }
  }

  bool _isValidSession(
    AuthenticatedSession candidate, {
    HomeserverAddress? expectedHomeserver,
  }) {
    final userId = candidate.userId.trim();
    final deviceId = candidate.deviceId.trim();
    final separator = userId.indexOf(':');
    if (userId != candidate.userId ||
        !userId.startsWith('@') ||
        separator <= 1 ||
        separator == userId.length - 1 ||
        userId.contains(RegExp(r'\s')) ||
        deviceId.isEmpty ||
        deviceId != candidate.deviceId) {
      return false;
    }
    return expectedHomeserver == null ||
        candidate.homeserver.uri == expectedHomeserver.uri;
  }

  void changeHomeserver() {
    if (isBusy) return;
    errorMessage.value = null;
    loginMethods.value = null;
    session.value = null;
  }

  void dispose() {
    progress.dispose();
    loginMethods.dispose();
    session.dispose();
    errorMessage.dispose();
  }
}
