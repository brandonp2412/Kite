import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class MatrixRustAuthSessionApi implements MatrixNativeAuthSessionApi {
  factory MatrixRustAuthSessionApi({
    required MatrixHomeserverDiscovery homeserverDiscovery,
    required MatrixRustAuthenticationBridge authenticationBridge,
    required MatrixRustBridge nativeBridge,
    required Directory rootDirectory,
    required MatrixSdkStoreSecretResolver resolveStoreSecret,
    required MatrixSdkStoreConfiguration Function(String accountId)
    storeConfigurationForAccount,
    String Function()? stagingIdFactory,
  }) {
    return MatrixRustAuthSessionApi._(
      homeserverDiscovery,
      authenticationBridge,
      nativeBridge,
      rootDirectory,
      resolveStoreSecret,
      storeConfigurationForAccount,
      stagingIdFactory ?? _secureStagingId,
    );
  }

  MatrixRustAuthSessionApi._(
    this._homeserverDiscovery,
    this._authenticationBridge,
    this._nativeBridge,
    this._rootDirectory,
    this._resolveStoreSecret,
    this._storeConfigurationForAccount,
    this._stagingIdFactory,
  );

  static const String encryptionKeyId = 'kite-matrix-store-v1';

  final MatrixHomeserverDiscovery _homeserverDiscovery;
  final MatrixRustAuthenticationBridge _authenticationBridge;
  final MatrixRustBridge _nativeBridge;
  final Directory _rootDirectory;
  final MatrixSdkStoreSecretResolver _resolveStoreSecret;
  final MatrixSdkStoreConfiguration Function(String accountId)
  _storeConfigurationForAccount;
  final String Function() _stagingIdFactory;

  _PendingMatrixLogin? _pendingLogin;

  File get _sessionFile => File('${_rootDirectory.path}/session.json');

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    final discovered = await _homeserverDiscovery.discover(
      homeserver.toString(),
    );
    final native = await _authenticationBridge.discoverAuthentication(
      discovered.homeserverBaseUrl,
    );
    return MatrixSdkAuthenticationDiscovery(
      homeserver: native.homeserver,
      methods: <MatrixSdkAuthenticationMethod>{
        if (native.passwordAvailable) MatrixSdkAuthenticationMethod.password,
      },
    );
  }

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    if (_pendingLogin != null) {
      throw StateError('A Matrix login is already awaiting persistence');
    }

    final existing = await _readSessionRecord();
    if (existing != null &&
        username.trim() == existing.userId &&
        homeserver == existing.homeserver) {
      final configuration = _storeConfigurationForAccount(existing.userId);
      final existingStore = Directory(configuration.storePath);
      if (configuration.encryptionKeyId == encryptionKeyId &&
          await existingStore.exists()) {
        final secret = await _resolveStoreSecret(encryptionKeyId);
        MatrixRustClient? client;
        try {
          client = await _nativeBridge.openEncryptedClient(
            homeserver: homeserver,
            storePath: existingStore.path,
            storePassphrase: secret,
          );
          final result = await _loginWithPassword(
            client,
            username: username,
            password: password,
          );
          if (result.userId != existing.userId ||
              result.deviceId != existing.deviceId) {
            throw StateError(
              'Matrix reauthentication changed the existing account or device',
            );
          }
          final session = MatrixSdkSessionDescriptor(
            userId: result.userId,
            deviceId: result.deviceId,
            homeserver: homeserver,
          );
          _pendingLogin = _PendingMatrixLogin.existing(session: session);
          return session;
        } finally {
          await client?.close();
        }
      }
    }

    final stagingRoot = Directory(
      '${_rootDirectory.path}/login-staging/${_stagingIdFactory()}',
    );
    final storeDirectory = Directory('${stagingRoot.path}/matrix-sdk');
    await stagingRoot.create(recursive: true);
    final secret = await _resolveStoreSecret(encryptionKeyId);
    MatrixRustClient? client;
    try {
      client = await _nativeBridge.openEncryptedClient(
        homeserver: homeserver,
        storePath: storeDirectory.path,
        storePassphrase: secret,
      );
      final result = await _loginWithPassword(
        client,
        username: username,
        password: password,
      );
      final session = MatrixSdkSessionDescriptor(
        userId: result.userId,
        deviceId: result.deviceId,
        homeserver: homeserver,
      );
      _pendingLogin = _PendingMatrixLogin(
        session: session,
        stagingRoot: stagingRoot,
        storeDirectory: storeDirectory,
      );
      return session;
    } catch (_) {
      await _deleteOwnedStagingDirectory(stagingRoot);
      rethrow;
    } finally {
      await client?.close();
    }
  }

  Future<MatrixRustLoginResult> _loginWithPassword(
    MatrixRustClient client, {
    required String username,
    required String password,
  }) async {
    try {
      return await client.loginWithPassword(
        username: username,
        password: password,
      );
    } on MatrixRustNativeException catch (error) {
      if (error.code == 'authentication_rejected' ||
          error.code == 'invalid_credentials') {
        throw MatrixAccountSdkException(error.publicMessage);
      }
      rethrow;
    }
  }

  @override
  Future<MatrixSdkSessionDescriptor?> restoreSession() async {
    final record = await _readSessionRecord();
    if (record == null) return null;
    final configuration = _storeConfigurationForAccount(record.userId);
    if (configuration.encryptionKeyId != encryptionKeyId) return null;
    if (!await Directory(configuration.storePath).exists()) return null;
    return record.toDescriptor();
  }

  @override
  Future<void> persistSession(MatrixSdkSessionDescriptor session) async {
    final pending = _pendingLogin;
    if (pending == null || !_sameSession(pending.session, session)) {
      final existing = await _readSessionRecord();
      if (existing != null && _sameSession(existing.toDescriptor(), session)) {
        return;
      }
      throw StateError(
        'Matrix session is not backed by a completed native login',
      );
    }

    if (pending.usesExistingStore) {
      await _writeSessionRecord(_MatrixSessionRecord.fromDescriptor(session));
      _pendingLogin = null;
      return;
    }

    final configuration = _storeConfigurationForAccount(session.userId);
    if (configuration.encryptionKeyId != encryptionKeyId) {
      throw StateError(
        'Matrix account store key does not match login store key',
      );
    }
    final destination = Directory(configuration.storePath);
    if (await destination.exists()) {
      throw StateError('Matrix account store already exists');
    }
    await destination.parent.create(recursive: true);
    await pending.storeDirectory!.rename(destination.path);
    try {
      await _writeSessionRecord(_MatrixSessionRecord.fromDescriptor(session));
      _pendingLogin = null;
      await _deleteOwnedStagingDirectory(pending.stagingRoot!);
    } catch (_) {
      rethrow;
    }
  }

  @override
  Future<void> logoutSession(MatrixSdkSessionDescriptor session) async {
    final record = await _readSessionRecord();
    if (record == null || !_sameSession(record.toDescriptor(), session)) {
      throw StateError('Matrix session is not available for logout');
    }
    final configuration = _storeConfigurationForAccount(record.userId);
    if (configuration.encryptionKeyId != encryptionKeyId) {
      throw StateError(
        'Matrix account store key does not match login store key',
      );
    }
    final store = Directory(configuration.storePath);
    if (!await store.exists()) {
      throw StateError('Matrix account store is unavailable for logout');
    }

    final secret = await _resolveStoreSecret(encryptionKeyId);
    MatrixRustClient? client;
    try {
      client = await _nativeBridge.openEncryptedClient(
        homeserver: record.homeserver,
        storePath: store.path,
        storePassphrase: secret,
      );
      if (client is! MatrixRustLogoutClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support session logout',
        );
      }
      await (client as MatrixRustLogoutClient).logout();
    } finally {
      await client?.close();
    }
  }

  @override
  Future<void> clearSession() async {
    final pending = _pendingLogin;
    _pendingLogin = null;
    Object? cleanupFailure;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        cleanupFailure ??= error;
      }
    }

    final pendingStagingRoot = pending?.stagingRoot;
    if (pendingStagingRoot != null) {
      await attempt(() => _deleteOwnedStagingDirectory(pendingStagingRoot));
    }

    final record = await _readSessionRecord();
    if (record != null) {
      final configuration = _storeConfigurationForAccount(record.userId);
      if (configuration.encryptionKeyId != encryptionKeyId) {
        cleanupFailure ??= StateError(
          'Matrix account store key does not match login store key',
        );
      } else {
        final store = Directory(configuration.storePath);
        await attempt(() async {
          if (await store.exists()) await store.delete(recursive: true);
        });
      }
    }

    final file = _sessionFile;
    await attempt(() async {
      if (await file.exists()) await file.delete();
    });

    if (cleanupFailure != null) {
      throw StateError('Matrix local session cleanup failed');
    }
  }

  Future<_MatrixSessionRecord?> _readSessionRecord() async {
    final file = _sessionFile;
    if (!await file.exists()) return null;
    try {
      final payload = await file.readAsString();
      final decoded = await Isolate.run<Object?>(() => jsonDecode(payload));
      if (decoded is! Map<String, dynamic>) return null;
      return _MatrixSessionRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSessionRecord(_MatrixSessionRecord record) async {
    await _rootDirectory.create(recursive: true);
    final target = _sessionFile;
    final temporary = File('${target.path}.tmp');
    final json = record.toJson();
    final payload = await Isolate.run<String>(() => jsonEncode(json));
    await temporary.writeAsString(payload, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  static Future<void> _deleteOwnedStagingDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static bool _sameSession(
    MatrixSdkSessionDescriptor left,
    MatrixSdkSessionDescriptor right,
  ) {
    return left.userId == right.userId &&
        left.deviceId == right.deviceId &&
        left.homeserver == right.homeserver;
  }

  static String _secureStagingId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

final class _PendingMatrixLogin {
  const _PendingMatrixLogin({
    required this.session,
    required this.stagingRoot,
    required this.storeDirectory,
  });

  const _PendingMatrixLogin.existing({required this.session})
    : stagingRoot = null,
      storeDirectory = null;

  final MatrixSdkSessionDescriptor session;
  final Directory? stagingRoot;
  final Directory? storeDirectory;

  bool get usesExistingStore => stagingRoot == null;
}

final class _MatrixSessionRecord {
  const _MatrixSessionRecord({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  factory _MatrixSessionRecord.fromDescriptor(
    MatrixSdkSessionDescriptor descriptor,
  ) {
    return _MatrixSessionRecord(
      userId: descriptor.userId,
      deviceId: descriptor.deviceId,
      homeserver: descriptor.homeserver,
    );
  }

  factory _MatrixSessionRecord.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final deviceId = json['deviceId'];
    final homeserver = json['homeserver'];
    if (userId is! String ||
        userId.isEmpty ||
        deviceId is! String ||
        deviceId.isEmpty ||
        homeserver is! String) {
      throw const FormatException('Invalid Matrix session metadata');
    }
    final uri = Uri.tryParse(homeserver);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      throw const FormatException('Invalid Matrix session homeserver');
    }
    return _MatrixSessionRecord(
      userId: userId,
      deviceId: deviceId,
      homeserver: uri,
    );
  }

  final String userId;
  final String deviceId;
  final Uri homeserver;

  MatrixSdkSessionDescriptor toDescriptor() {
    return MatrixSdkSessionDescriptor(
      userId: userId,
      deviceId: deviceId,
      homeserver: homeserver,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'deviceId': deviceId,
    'homeserver': homeserver.toString(),
  };
}
