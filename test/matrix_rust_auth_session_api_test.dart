import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
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
      expect(
        discovery.methods,
        contains(MatrixSdkAuthenticationMethod.password),
      );
      expect(
        bridge.lastDiscoveryInput,
        Uri.parse('https://matrix.example.org'),
      );

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

  test('soft-login reuses the existing encrypted account store', () async {
    final root = await Directory.systemTemp.createTemp('kite-auth-reauth-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final bridge = _FakeRustBridge();
    final api = _api(root, bridge);
    final session = await api.loginWithPassword(
      homeserver: Uri.parse('https://matrix.example.org'),
      username: 'alice',
      password: 'secret',
    );
    await api.persistSession(session);
    final configuration = _configuration(root, session.userId);
    final originalStore = Directory(configuration.storePath);
    expect(await originalStore.exists(), isTrue);

    final refreshed = await api.loginWithPassword(
      homeserver: session.homeserver,
      username: session.userId,
      password: 'new-secret',
    );
    await api.persistSession(refreshed);

    expect(refreshed.userId, session.userId);
    expect(refreshed.deviceId, session.deviceId);
    expect(await originalStore.exists(), isTrue);
    expect(await api.restoreSession(), isNotNull);
  });

  test('native discovery can reject password login after well-known', () async {
    final root = await Directory.systemTemp.createTemp('kite-auth-discovery-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final bridge = _FakeRustBridge(passwordAvailable: false);
    final api = _api(root, bridge);

    final discovery = await api.discoverAuthentication(
      Uri.parse('https://example.org'),
    );

    expect(bridge.lastDiscoveryInput, Uri.parse('https://matrix.example.org'));
    expect(discovery.methods, isEmpty);
  });

  test(
    'credential rejection is translated into an account SDK failure',
    () async {
      final root = await Directory.systemTemp.createTemp('kite-auth-rejected-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final bridge = _FakeRustBridge(
        loginError: const MatrixRustNativeException(
          code: 'authentication_rejected',
          publicMessage: 'Matrix login was rejected.',
        ),
      );
      final api = _api(root, bridge);

      await expectLater(
        api.loginWithPassword(
          homeserver: Uri.parse('https://matrix.example.org'),
          username: 'alice',
          password: 'wrong-password',
        ),
        throwsA(
          isA<MatrixAccountSdkException>().having(
            (error) => error.publicMessage,
            'publicMessage',
            'Matrix login was rejected.',
          ),
        ),
      );

      expect(
        await Directory('${root.path}/login-staging/deterministic-staging')
            .exists(),
        isFalse,
      );
    },
  );

  test('non-credential native login failures remain native failures', () async {
    final root = await Directory.systemTemp.createTemp(
      'kite-auth-native-fail-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final bridge = _FakeRustBridge(
      loginError: const MatrixRustNativeException(
        code: 'native_operation_failed',
        publicMessage: 'The Matrix native operation failed.',
      ),
    );
    final api = _api(root, bridge);

    await expectLater(
      api.loginWithPassword(
        homeserver: Uri.parse('https://matrix.example.org'),
        username: 'alice',
        password: 'secret',
      ),
      throwsA(
        isA<MatrixRustNativeException>().having(
          (error) => error.code,
          'code',
          'native_operation_failed',
        ),
      ),
    );
  });

  test('native logout invalidates the persisted Matrix session', () async {
    final root = await Directory.systemTemp.createTemp('kite-auth-logout-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final bridge = _FakeRustBridge();
    final api = _api(root, bridge);
    final session = await api.loginWithPassword(
      homeserver: Uri.parse('https://matrix.example.org'),
      username: 'alice',
      password: 'secret',
    );
    await api.persistSession(session);

    await api.logoutSession(session);

    expect(bridge.logoutCalls, 1);
    expect(await api.restoreSession(), isNotNull);
  });

  test(
    'clearing session removes metadata and the encrypted account store',
    () async {
      final root = await Directory.systemTemp.createTemp('kite-auth-clear-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final bridge = _FakeRustBridge();
      final api = _api(root, bridge);
      final session = await api.loginWithPassword(
        homeserver: Uri.parse('https://matrix.example.org'),
        username: 'alice',
        password: 'secret',
      );
      await api.persistSession(session);
      final configuration = _configuration(root, session.userId);
      expect(await Directory(configuration.storePath).exists(), isTrue);

      await api.clearSession();

      expect(await api.restoreSession(), isNull);
      expect(await File('${root.path}/session.json').exists(), isFalse);
      expect(await Directory(configuration.storePath).exists(), isFalse);

      final replacement = await api.loginWithPassword(
        homeserver: Uri.parse('https://matrix.example.org'),
        username: 'alice',
        password: 'new-secret',
      );
      await api.persistSession(replacement);
      expect(await Directory(configuration.storePath).exists(), isTrue);
    },
  );
}

MatrixRustAuthSessionApi _api(Directory root, _FakeRustBridge bridge) {
  return MatrixRustAuthSessionApi(
    homeserverDiscovery: const MatrixHomeserverDiscovery(
      _FakeWellKnownClient(),
    ),
    authenticationBridge: bridge,
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

final class _FakeRustBridge
    implements MatrixRustBridge, MatrixRustAuthenticationBridge {
  _FakeRustBridge({this.passwordAvailable = true, this.loginError});

  final bool passwordAvailable;
  final MatrixRustNativeException? loginError;
  String? lastSecret;
  Uri? lastDiscoveryInput;
  int logoutCalls = 0;

  @override
  Future<MatrixRustAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    lastDiscoveryInput = homeserver;
    return MatrixRustAuthenticationDiscovery(
      homeserver: homeserver,
      passwordAvailable: passwordAvailable,
    );
  }

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
    return _FakeRustClient(
      onLogout: () => logoutCalls += 1,
      loginError: loginError,
    );
  }
}

final class _FakeRustClient
    implements MatrixRustClient, MatrixRustLogoutClient {
  _FakeRustClient({required this.onLogout, this.loginError});

  final void Function() onLogout;
  final MatrixRustNativeException? loginError;
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) async {
    final error = loginError;
    if (error != null) throw error;
    if ((username != 'alice' && username != '@alice:example.org') ||
        password.isEmpty) {
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
  Future<void> logout() async {
    onLogout();
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
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
