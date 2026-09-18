import 'package:kite/core/async_controller_lifecycle.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals.dart';

enum AuthenticationProgress { idle, discovering, signingIn }

final class AuthenticationController with AsyncControllerLifecycle {
  AuthenticationController(this._gateway);

  final AuthenticationGateway _gateway;

  final progress = signal(AuthenticationProgress.idle);
  final loginMethods = signal<HomeserverLoginMethods?>(null);
  final session = signal<AuthenticatedSession?>(null);
  final errorMessage = signal<String?>(null);

  bool get isBusy => progress.value != AuthenticationProgress.idle;

  Future<void> discover(String rawHomeserver) async {
    if (controllerDisposed || isBusy) return;

    errorMessage.value = null;
    HomeserverAddress homeserver;
    try {
      homeserver = HomeserverAddress.parse(rawHomeserver);
    } on AuthenticationInputException catch (error) {
      errorMessage.value = error.publicMessage;
      return;
    }

    final lifecycle = captureControllerLifecycle();
    loginMethods.value = null;
    session.value = null;
    progress.value = AuthenticationProgress.discovering;
    try {
      final discovered = await _gateway.discover(homeserver);
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      loginMethods.value = discovered;
    } on AuthenticationException catch (error) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = error.publicMessage;
      }
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not connect to that homeserver.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        progress.value = AuthenticationProgress.idle;
      }
    }
  }

  Future<void> loginWithPassword({
    required String username,
    required String password,
    String? expectedUserId,
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
      expectedUserId: expectedUserId,
    );
  }

  Future<void> loginWithOidc({String? expectedUserId}) async {
    final methods = loginMethods.value;
    if (isBusy || methods == null) return;
    if (!methods.supports(AuthenticationMethod.oidc)) {
      errorMessage.value = 'This homeserver does not support OIDC login.';
      return;
    }
    await _runSignIn(
      () => _gateway.loginWithOidc(homeserver: methods.homeserver),
      expectedHomeserver: methods.homeserver,
      expectedUserId: expectedUserId,
    );
  }

  Future<void> loginWithSso({String? expectedUserId}) async {
    final methods = loginMethods.value;
    if (isBusy || methods == null) return;
    if (!methods.supports(AuthenticationMethod.sso)) {
      errorMessage.value = 'This homeserver does not support SSO login.';
      return;
    }
    await _runSignIn(
      () => _gateway.loginWithSso(homeserver: methods.homeserver),
      expectedHomeserver: methods.homeserver,
      expectedUserId: expectedUserId,
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
    String? expectedUserId,
  }) async {
    if (controllerDisposed) return;
    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    session.value = null;
    progress.value = AuthenticationProgress.signingIn;
    try {
      final authenticated = await action();
      if (!isControllerLifecycleCurrent(lifecycle)) return;
      if (!_isValidSession(
        authenticated,
        expectedHomeserver: expectedHomeserver,
        expectedUserId: expectedUserId,
      )) {
        session.value = null;
        errorMessage.value =
            expectedUserId != null && authenticated.userId != expectedUserId
            ? 'Sign in as $expectedUserId to continue.'
            : 'Kite received an invalid authentication session.';
        return;
      }
      session.value = authenticated;
    } on AuthenticationException catch (error) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = error.publicMessage;
      }
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value =
            'Sign in failed. Check your details and try again.';
      }
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        progress.value = AuthenticationProgress.idle;
      }
    }
  }

  bool _isValidSession(
    AuthenticatedSession candidate, {
    HomeserverAddress? expectedHomeserver,
    String? expectedUserId,
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
    if (expectedHomeserver != null &&
        candidate.homeserver.uri != expectedHomeserver.uri) {
      return false;
    }
    return expectedUserId == null || candidate.userId == expectedUserId;
  }

  void changeHomeserver() {
    if (controllerDisposed || isBusy) return;
    errorMessage.value = null;
    loginMethods.value = null;
    session.value = null;
  }

  void dispose() {
    if (!disposeControllerLifecycle()) return;
    progress.dispose();
    loginMethods.dispose();
    session.dispose();
    errorMessage.dispose();
  }
}
