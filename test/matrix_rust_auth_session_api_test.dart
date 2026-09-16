import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_rust_auth_session_api.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  test(
    'real auth adapter promotes encrypted native store and restores metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('kite-auth-session-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final bridge = _FakeRustBridge();
      final api = _api(root, bridge);

      final discovery = await api.discoverAuthentication(
        Uri.parse('https://example.org'),
      );
      expect(discovery.homeserver, Uri.parse('https://matrix.example.org'));

      final session = await api.loginWithPassword(
        homeserver: discovery.homeserver,
        username: 'alice',
        password: 'super-secret-password',
      );
      expect(session.userId, '@alice:example.org');
      expect(bridge.lastSecret, 'stable-store-secret');

      await api.persistSession(session);

      final configuration = _configuration(root, session.userId);
      expect(await Directory(configuration.storePath).exists(), isTrue);
      final metadata = await File('${root.path}/session.json').readAsString();
      expect(metadata, contains('@alice:example.org'));
      expect(metadata, isNot(contains('super-secret-password')));
      expect(metadata, isNot(contains('stable-store-secret')));

      final restored = await _api(root, _FakeRustBridge()).restoreSession();
      expect(restored?.userId, session.userId);
      expect(restored?.deviceId, session.deviceId);
      expect(restored?.homeserver, session.homeserver);
    },
  );

  test(
    'clearing session removes restore metadata without exposing native secrets',
    () async {
      final root = await Directory.systemTemp.createTemp('kite-auth-clear-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final api = _api(root, _FakeRustBridge());
      final session = await api.loginWithPassword(
        homeserver: Uri.parse('https://matrix.example.org'),
        username: 'alice',
        password: 'secret',
      );
      await api.persistSession(session);
      await api.clearSession();

      expect(await api.restoreSession(), isNull);
      expect(await File('${root.path}/session.json').exists(), isFalse);
    },
  );
}

MatrixRustAuthSessionApi _api(Directory root, MatrixRustBridge bridge) {
  return MatrixRustAuthSessionApi(
    homeserverDiscovery: const MatrixHomeserverDiscovery(
      _FakeWellKnownClient(),
    ),
    nativeBridge: bridge,
    rootDirectory: root,
    resolveStoreSecret: (_) async => 'stable-store-secret',
    storeConfigurationForAccount: (accountId) =>
        _configuration(root, accountId),
    stagingIdFactory: () => 'deterministic-staging',
  );
}

MatrixSdkStoreConfiguration _configuration(Directory root, String accountId) {
  return MatrixSdkStoreConfiguration(
    accountId: accountId,
    storePath:
        '${root.path}/matrix-sdk/${Uri.encodeComponent(accountId)}/matrix-sdk',
    encryptionKeyId: MatrixRustAuthSessionApi.encryptionKeyId,
  );
}

final class _FakeWellKnownClient implements MatrixWellKnownClient {
  const _FakeWellKnownClient();

  @override
  Future<Map<String, Object?>?> fetchClientConfiguration(Uri uri) async {
    return <String, Object?>{
      'm.homeserver': <String, Object?>{
        'base_url': 'https://matrix.example.org',
      },
    };
  }
}

final class _FakeRustBridge implements MatrixRustBridge {
  String? lastSecret;

  @override
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  }) async {
    lastSecret = storePassphrase;
    final directory = Directory(storePath);
    await directory.create(recursive: true);
    await File('${directory.path}/native-session').writeAsString('encrypted');
    return _FakeRustClient();
  }
}

final class _FakeRustClient implements MatrixRustClient {
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) async {
    if (username != 'alice' || password.isEmpty) {
      throw StateError('login failed');
    }
    return const MatrixRustLoginResult(
      userId: '@alice:example.org',
      deviceId: 'DEVICE',
    );
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    throw UnimplementedError();
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
