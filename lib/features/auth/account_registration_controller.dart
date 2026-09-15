import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals.dart';

sealed class AccountRegistrationStep {
  const AccountRegistrationStep();
}

final class RegistrationCredentialsStep extends AccountRegistrationStep {
  const RegistrationCredentialsStep();
}

final class RegistrationInteractiveStep extends AccountRegistrationStep {
  const RegistrationInteractiveStep({required this.publicInstructions});

  final String publicInstructions;
}

final class RegistrationCompleteStep extends AccountRegistrationStep {
  const RegistrationCompleteStep(this.session);

  final AuthenticatedSession session;
}

abstract interface class AccountRegistrationGateway {
  /// Starts the SDK-owned registration flow for [homeserver].
  ///
  /// The gateway is responsible for Matrix UIAA/server-specific registration
  /// semantics. Kite only renders the SDK boundary's current public step.
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver);

  /// Supplies credentials to the SDK-owned registration flow. Passwords must
  /// remain transient and must never be logged or persisted by Flutter.
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  });

  /// Continues SDK-owned interactive authentication such as terms, email,
  /// CAPTCHA, or a browser handoff. Any secret callback data stays inside the
  /// gateway boundary.
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  });
}

final class AccountRegistrationController {
  factory AccountRegistrationController({
    required HomeserverAddress homeserver,
    required AccountRegistrationGateway gateway,
  }) => AccountRegistrationController._(homeserver, gateway);

  AccountRegistrationController._(this._homeserver, this._gateway);

  final HomeserverAddress _homeserver;
  final AccountRegistrationGateway _gateway;

  final step = signal<AccountRegistrationStep?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  HomeserverAddress get homeserver => _homeserver;

  Future<bool> begin() {
    return _run(
      () => _gateway.begin(_homeserver),
      failureMessage: 'Kite could not start account registration.',
    );
  }

  Future<bool> submitCredentials({
    required String username,
    required String password,
  }) {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      errorMessage.value = 'Enter a username and password.';
      return Future<bool>.value(false);
    }
    if (step.value is! RegistrationCredentialsStep) {
      errorMessage.value = 'Registration is not ready for credentials yet.';
      return Future<bool>.value(false);
    }
    return _run(
      () => _gateway.submitCredentials(
        homeserver: _homeserver,
        username: normalizedUsername,
        password: password,
      ),
      failureMessage: 'Kite could not create that account.',
    );
  }

  Future<bool> continueInteractiveAuthentication() {
    if (step.value is! RegistrationInteractiveStep) {
      errorMessage.value = 'Registration is not waiting for verification.';
      return Future<bool>.value(false);
    }
    return _run(
      () => _gateway.continueInteractiveAuthentication(homeserver: _homeserver),
      failureMessage: 'Kite could not continue account registration.',
    );
  }

  Future<bool> _run(
    Future<AccountRegistrationStep> Function() action, {
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (!_isValidStep(next)) {
        errorMessage.value = 'Kite received an invalid registration state.';
        return false;
      }
      step.value = next;
      return true;
    } on AuthenticationException catch (error) {
      errorMessage.value = error.publicMessage;
      return false;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  bool _isValidStep(AccountRegistrationStep candidate) {
    if (candidate case RegistrationInteractiveStep(:final publicInstructions)) {
      return publicInstructions.trim().isNotEmpty;
    }
    if (candidate case RegistrationCompleteStep(:final session)) {
      final userId = session.userId.trim();
      return userId == session.userId &&
          userId.startsWith('@') &&
          userId.contains(':') &&
          !userId.contains(RegExp(r'\s')) &&
          session.deviceId.trim().isNotEmpty &&
          session.homeserver.uri == _homeserver.uri;
    }
    return true;
  }

  void dispose() {
    step.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
