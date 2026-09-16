import 'dart:io';

import 'package:flutter/services.dart';

final class PlatformMatrixBootstrapGateway {
  const PlatformMatrixBootstrapGateway([
    this._channel = const MethodChannel('nz.presley.kite/matrix_bootstrap'),
  ]);

  final MethodChannel _channel;

  Future<Directory> dataRoot() async {
    final path = await _channel.invokeMethod<String>('dataRoot');
    if (path == null || path.trim().isEmpty || path.contains('\u0000')) {
      throw StateError('Matrix data root is unavailable');
    }
    return Directory(path);
  }

  Future<String> resolveStoreSecret(String keyId) async {
    final normalized = keyId.trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      throw ArgumentError.value(keyId, 'keyId', 'must be non-empty and C-safe');
    }
    final secret = await _channel.invokeMethod<String>(
      'resolveStoreSecret',
      <String, Object?>{'keyId': normalized},
    );
    if (secret == null || secret.isEmpty || secret.contains('\u0000')) {
      throw StateError('Matrix store secret is unavailable');
    }
    return secret;
  }
}
