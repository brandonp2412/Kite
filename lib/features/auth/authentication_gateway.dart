import 'dart:async';

enum AuthenticationMethod { password, oidc, sso }

final class HomeserverAddress {
  const HomeserverAddress._(this.uri);

  final Uri uri;

  static HomeserverAddress parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const AuthenticationInputException('Enter a homeserver.');
    }

    final candidate = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    if (candidate == null || candidate.host.isEmpty) {
      throw const AuthenticationInputException(
        'Enter a valid homeserver address.',
      );
    }
    if (candidate.scheme != 'https') {
      throw const AuthenticationInputException(
        'Kite requires an HTTPS homeserver.',
      );
    }
    if (candidate.userInfo.isNotEmpty ||
        candidate.hasQuery ||
        candidate.hasFragment) {
      throw const AuthenticationInputException(
        'Homeserver addresses cannot include credentials, queries, or fragments.',
      );
    }

    final normalized = candidate.replace(
      path: candidate.path == '/' ? '' : candidate.path,
    );
    return HomeserverAddress._(normalized);
  }

  String get displayName => uri.host;

  @override
  String toString() => uri.toString();
}

final class HomeserverLoginMethods {
  const HomeserverLoginMethods({
    required this.homeserver,
    required this.methods,
    this.registrationAvailable = false,
  });

  final HomeserverAddress homeserver;
  final Set<AuthenticationMethod> methods;
  final bool registrationAvailable;

  bool supports(AuthenticationMethod method) => methods.contains(method);
}

final class AuthenticatedSession {
  const AuthenticatedSession({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  final String userId;
  final String deviceId;
  final HomeserverAddress homeserver;

  @override
  String toString() =>
      'AuthenticatedSession(userId: $userId, deviceId: $deviceId, homeserver: $homeserver)';
}

sealed class AuthenticationException implements Exception {
  const AuthenticationException(this.publicMessage);

  final String publicMessage;
}

final class AuthenticationInputException extends AuthenticationException {
  const AuthenticationInputException(super.publicMessage);
}

final class AuthenticationRejectedException extends AuthenticationException {
  const AuthenticationRejectedException(super.publicMessage);
}

abstract interface class AuthenticationGateway {
  /// Resolves authentication through the Matrix SDK. The returned homeserver
  /// may differ from [homeserver] when trusted `.well-known` discovery selects
  /// the actual client API base URL.
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver);

  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  });

  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  });

  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  });

  /// Delegates an opaque device-to-device login QR payload to the Matrix SDK.
  /// Kite must not parse, persist, or log [qrCodeData].
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData);
}
