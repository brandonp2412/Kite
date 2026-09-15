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

    progress.value = AuthenticationProgress.discovering;
    try {
      loginMethods.value = await _gateway.discover(homeserver);
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
    );
  }

  Future<void> loginWithQrCode(String qrCodeData) async {
    if (isBusy) return;
    if (qrCodeData.isEmpty) {
      errorMessage.value = 'Scan a valid Matrix sign-in QR code.';
      return;
    }
    await _runSignIn(() => _gateway.loginWithQrCode(qrCodeData));
  }

  Future<void> _runSignIn(
    Future<AuthenticatedSession> Function() action,
  ) async {
    errorMessage.value = null;
    progress.value = AuthenticationProgress.signingIn;
    try {
      session.value = await action();
    } on AuthenticationException catch (error) {
      errorMessage.value = error.publicMessage;
    } catch (_) {
      errorMessage.value = 'Sign in failed. Check your details and try again.';
    } finally {
      progress.value = AuthenticationProgress.idle;
    }
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
