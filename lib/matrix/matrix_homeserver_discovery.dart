import 'dart:collection';

final class MatrixHomeserverDiscoveryResult {
  const MatrixHomeserverDiscoveryResult({
    required this.enteredServer,
    required this.homeserverBaseUrl,
    required this.usedWellKnown,
  });

  final Uri enteredServer;
  final Uri homeserverBaseUrl;
  final bool usedWellKnown;
}

final class MatrixHomeserverDiscoveryException implements Exception {
  const MatrixHomeserverDiscoveryException(this.message);

  final String message;

  @override
  String toString() => 'MatrixHomeserverDiscoveryException: $message';
}

abstract interface class MatrixWellKnownClient {
  Future<Map<String, Object?>?> fetchClientConfiguration(Uri uri);
}

final class MatrixHomeserverDiscovery {
  const MatrixHomeserverDiscovery(this._client);

  final MatrixWellKnownClient _client;

  Future<MatrixHomeserverDiscoveryResult> discover(String server) async {
    final enteredServer = _normaliseServer(server);
    final wellKnownUri = enteredServer.resolve('/.well-known/matrix/client');
    final document = await _client.fetchClientConfiguration(wellKnownUri);
    if (document == null) {
      return MatrixHomeserverDiscoveryResult(
        enteredServer: enteredServer,
        homeserverBaseUrl: enteredServer,
        usedWellKnown: false,
      );
    }

    final homeserver = document['m.homeserver'];
    if (homeserver == null) {
      return MatrixHomeserverDiscoveryResult(
        enteredServer: enteredServer,
        homeserverBaseUrl: enteredServer,
        usedWellKnown: false,
      );
    }
    if (homeserver is! Map) {
      throw const MatrixHomeserverDiscoveryException(
        'm.homeserver must be an object',
      );
    }

    final typedHomeserver = UnmodifiableMapView<String, Object?>(
      homeserver.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
    final baseUrl = typedHomeserver['base_url'];
    if (baseUrl is! String || baseUrl.trim().isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'm.homeserver.base_url must be a non-empty string',
      );
    }

    final discovered = _parseHomeserverBaseUri(baseUrl.trim());
    return MatrixHomeserverDiscoveryResult(
      enteredServer: enteredServer,
      homeserverBaseUrl: discovered,
      usedWellKnown: true,
    );
  }

  static Uri _normaliseServer(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'homeserver must not be empty',
      );
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return _parseHomeserverBaseUri(candidate);
  }

  static Uri _parseHomeserverBaseUri(String value) {
    final uri = _parseAbsoluteHttpUri(value);
    if (uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'homeserver must not include credentials, query parameters, or fragments',
      );
    }
    return uri;
  }

  static Uri _parseAbsoluteHttpUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw MatrixHomeserverDiscoveryException(
        'invalid homeserver URL: $value',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw MatrixHomeserverDiscoveryException(
        'unsupported homeserver URL scheme: ${uri.scheme}',
      );
    }
    return uri;
  }
}
