import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:kite/matrix/matrix_homeserver_discovery.dart';

final class IoMatrixWellKnownClient implements MatrixWellKnownClient {
  const IoMatrixWellKnownClient({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  @override
  Future<Map<String, Object?>?> fetchClientConfiguration(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = await utf8.decoder.bind(response).join().timeout(timeout);
      final decoded = await Isolate.run<Object?>(() => jsonDecode(payload));
      if (decoded is! Map) {
        throw const FormatException('Invalid Matrix .well-known response');
      }
      return decoded.map<String, Object?>(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    } finally {
      client.close(force: true);
    }
  }
}
