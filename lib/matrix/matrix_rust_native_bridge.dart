import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

const int kiteMatrixNativeAbiVersion = 8;

const Duration _matrixRustSyncPollTimeout = Duration(seconds: 5);
const int _matrixRustMaxRetryDelaySeconds = 30;

enum _MatrixRustSyncFailureCode {
  unknownPosition,
  unknownToken,
  sessionPersistence,
  refreshToken,
  authenticationRequired,
  network,
  api,
  stateStore,
  eventCacheStore,
  other,
}

final class _MatrixRustSyncFailure implements Exception {
  const _MatrixRustSyncFailure(this.code);

  final _MatrixRustSyncFailureCode code;

  bool get isPermanent =>
      code == _MatrixRustSyncFailureCode.unknownPosition ||
      code == _MatrixRustSyncFailureCode.unknownToken ||
      code == _MatrixRustSyncFailureCode.sessionPersistence ||
      code == _MatrixRustSyncFailureCode.refreshToken ||
      code == _MatrixRustSyncFailureCode.authenticationRequired ||
      code == _MatrixRustSyncFailureCode.stateStore ||
      code == _MatrixRustSyncFailureCode.eventCacheStore;

  bool get isSessionExpired =>
      code == _MatrixRustSyncFailureCode.unknownToken ||
      code == _MatrixRustSyncFailureCode.refreshToken ||
      code == _MatrixRustSyncFailureCode.authenticationRequired;

  @override
  String toString() => 'Matrix Rust SDK sync failed (${code.name})';
}

_MatrixRustSyncFailure? _decodeMatrixRustSyncFailure(String payload) {
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final error = decoded['error'];
  if (error is! Map) return null;
  final code = error['code'];
  if (code is! String) return null;
  return _MatrixRustSyncFailure(switch (code) {
    'unknown_pos' => _MatrixRustSyncFailureCode.unknownPosition,
    'unknown_token' => _MatrixRustSyncFailureCode.unknownToken,
    'session_persist_failed' => _MatrixRustSyncFailureCode.sessionPersistence,
    'refresh_token_failed' => _MatrixRustSyncFailureCode.refreshToken,
    'authentication_required' =>
      _MatrixRustSyncFailureCode.authenticationRequired,
    'network_failed' => _MatrixRustSyncFailureCode.network,
    'api_failed' => _MatrixRustSyncFailureCode.api,
    'state_store_failed' => _MatrixRustSyncFailureCode.stateStore,
    'event_cache_store_failed' => _MatrixRustSyncFailureCode.eventCacheStore,
    _ => _MatrixRustSyncFailureCode.other,
  });
}

Duration _matrixRustRetryDelayForAttempt(int attempt) {
  var seconds = 1;
  for (var index = 1; index < attempt; index += 1) {
    if (seconds >= _matrixRustMaxRetryDelaySeconds) break;
    seconds *= 2;
    if (seconds > _matrixRustMaxRetryDelaySeconds) {
      seconds = _matrixRustMaxRetryDelaySeconds;
    }
  }
  return Duration(seconds: seconds);
}

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _ClientNewNative = Pointer<Void> Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientNewDart = Pointer<Void> Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSyncOnceNative = Pointer<Char> Function(
  Pointer<Void>,
  Uint64,
  Pointer<Char>,
  Uint64,
);
typedef _ClientSyncOnceDart = Pointer<Char> Function(
  Pointer<Void>,
  int,
  Pointer<Char>,
  int,
);
typedef _ClientPaginateNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _ClientPaginateDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _DiscoverAuthenticationNative = Pointer<Char> Function(Pointer<Char>);
typedef _DiscoverAuthenticationDart = Pointer<Char> Function(Pointer<Char>);
typedef _ClientLoginPasswordNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientLoginPasswordDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSendTextNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSendTextDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSessionOperationNative = Pointer<Char> Function(Pointer<Void>);
typedef _ClientSessionOperationDart = Pointer<Char> Function(Pointer<Void>);
typedef _StringFreeNative = Void Function(Pointer<Char> value);
typedef _StringFreeDart = void Function(Pointer<Char> value);
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

typedef MatrixSdkStoreSecretResolver = Future<String> Function(String keyId);
typedef MatrixRustSyncDelay = Future<void> Function(Duration duration);

final class MatrixRustLoginResult {
  const MatrixRustLoginResult({required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;
}

final class MatrixRustSendResult {
  const MatrixRustSendResult({required this.eventId});

  final String eventId;
}

final class MatrixRustRoomMember {
  const MatrixRustRoomMember({
    required this.userId,
    required this.displayName,
    required this.powerLevel,
  });

  final String userId;
  final String displayName;
  final int powerLevel;
}

final class MatrixRustNativeException implements Exception {
  const MatrixRustNativeException({
    required this.code,
    required this.publicMessage,
  });

  final String code;
  final String publicMessage;

  @override
  String toString() =>
      'MatrixRustNativeException(code: $code, detail: <redacted>)';
}

final class MatrixRustAuthenticationDiscovery {
  const MatrixRustAuthenticationDiscovery({
    required this.homeserver,
    required this.passwordAvailable,
  });

  final Uri homeserver;
  final bool passwordAvailable;
}

final class MatrixRustSessionDescriptor {
  const MatrixRustSessionDescriptor({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  final String userId;
  final String deviceId;
  final Uri homeserver;
}

Object? _decodeNativeEnvelope(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned an invalid response.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned an invalid response.',
    );
  }
  if (decoded['ok'] == true) return decoded['value'];
  final error = decoded['error'];
  if (error is Map<String, dynamic>) {
    final code = error['code'];
    final message = error['message'];
    if (code is String && message is String) {
      throw MatrixRustNativeException(code: code, publicMessage: message);
    }
  }
  throw const MatrixRustNativeException(
    code: 'native_operation_failed',
    publicMessage: 'The Matrix native operation failed.',
  );
}

MatrixRustSessionDescriptor _decodeSessionDescriptor(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned invalid session data.',
    );
  }
  final userId = value['userId'];
  final deviceId = value['deviceId'];
  final homeserver = value['homeserver'];
  final parsedHomeserver = homeserver is String
      ? Uri.tryParse(homeserver)
      : null;
  if (userId is! String ||
      userId.isEmpty ||
      deviceId is! String ||
      deviceId.isEmpty ||
      parsedHomeserver == null ||
      !parsedHomeserver.hasScheme) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned invalid session data.',
    );
  }
  return MatrixRustSessionDescriptor(
    userId: userId,
    deviceId: deviceId,
    homeserver: parsedHomeserver,
  );
}

String _readNativeString(
  Pointer<Char> value,
  _StringFreeDart freeString,
  String operation,
) {
  if (value == nullptr) {
    throw StateError('Matrix Rust SDK $operation returned no result');
  }
  try {
    return value.cast<Utf8>().toDartString();
  } finally {
    freeString(value);
  }
}

final class _MatrixNativeDiscoverAuthenticationOperation {
  const _MatrixNativeDiscoverAuthenticationOperation({
    required this.libraryPath,
    required this.homeserver,
  });

  final String libraryPath;
  final String homeserver;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final discover = library
        .lookupFunction<
          _DiscoverAuthenticationNative,
          _DiscoverAuthenticationDart
        >('kite_matrix_discover_authentication');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final homeserverUtf8 = homeserver.toNativeUtf8(allocator: calloc);
    try {
      return _readNativeString(
        discover(homeserverUtf8.cast<Char>()),
        freeString,
        'authentication discovery',
      );
    } finally {
      calloc.free(homeserverUtf8);
    }
  }
}

final class _MatrixNativeLoginPasswordOperation {
  const _MatrixNativeLoginPasswordOperation({
    required this.libraryPath,
    required this.address,
    required this.username,
    required this.password,
  });

  final String libraryPath;
  final int address;
  final String username;
  final String password;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final login = library
        .lookupFunction<_ClientLoginPasswordNative, _ClientLoginPasswordDart>(
          'kite_matrix_client_login_password',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final usernameUtf8 = username.toNativeUtf8(allocator: calloc);
    final passwordUtf8 = password.toNativeUtf8(allocator: calloc);
    final passwordBytes = passwordUtf8.cast<Uint8>().asTypedList(
      passwordUtf8.length + 1,
    );
    try {
      final value = login(
        Pointer<Void>.fromAddress(address),
        usernameUtf8.cast<Char>(),
        passwordUtf8.cast<Char>(),
      );
      return _readNativeString(value, freeString, 'password login');
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      calloc.free(passwordUtf8);
      calloc.free(usernameUtf8);
    }
  }
}

final class _MatrixNativeSendTextOperation {
  const _MatrixNativeSendTextOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.transactionId,
    required this.body,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String transactionId;
  final String body;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final send = library
        .lookupFunction<_ClientSendTextNative, _ClientSendTextDart>(
          'kite_matrix_client_send_text',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final transactionIdUtf8 = transactionId.toNativeUtf8(allocator: calloc);
    final bodyUtf8 = body.toNativeUtf8(allocator: calloc);
    try {
      final value = send(
        Pointer<Void>.fromAddress(address),
        roomIdUtf8.cast<Char>(),
        transactionIdUtf8.cast<Char>(),
        bodyUtf8.cast<Char>(),
      );
      return _readNativeString(value, freeString, 'text send');
    } finally {
      calloc.free(bodyUtf8);
      calloc.free(transactionIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeSessionOperation {
  const _MatrixNativeSessionOperation({
    required this.libraryPath,
    required this.address,
    required this.symbol,
    required this.operation,
  });

  final String libraryPath;
  final int address;
  final String symbol;
  final String operation;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final sessionOperation = library
        .lookupFunction<
          _ClientSessionOperationNative,
          _ClientSessionOperationDart
        >(symbol);
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    return _readNativeString(
      sessionOperation(Pointer<Void>.fromAddress(address)),
      freeString,
      operation,
    );
  }
}

final class _MatrixNativeSyncOperation {
  const _MatrixNativeSyncOperation({
    required this.libraryPath,
    required this.address,
    required this.timeoutMs,
    required this.since,
    required this.timelineEventLimit,
  });

  final String libraryPath;
  final int address;
  final int timeoutMs;
  final String? since;
  final int timelineEventLimit;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final syncOnce = library
        .lookupFunction<_ClientSyncOnceNative, _ClientSyncOnceDart>(
          'kite_matrix_client_sync_once',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final sinceUtf8 = since?.toNativeUtf8(allocator: calloc);
    try {
      final value = syncOnce(
        Pointer<Void>.fromAddress(address),
        timeoutMs,
        sinceUtf8 == null
            ? Pointer<Char>.fromAddress(0)
            : sinceUtf8.cast<Char>(),
        timelineEventLimit,
      );
      if (value == nullptr) {
        throw StateError('Matrix Rust SDK sync failed');
      }
      try {
        return value.cast<Utf8>().toDartString();
      } finally {
        freeString(value);
      }
    } finally {
      if (sinceUtf8 != null) calloc.free(sinceUtf8);
    }
  }
}

final class _MatrixNativeRoomMembersOperation {
  const _MatrixNativeRoomMembersOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
  });

  final String libraryPath;
  final int address;
  final String roomId;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final roomMembers = library
        .lookupFunction<_ClientPaginateNative, _ClientPaginateDart>(
          'kite_matrix_client_room_members',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        roomMembers(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
        ),
        freeString,
        'room member lookup',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room member data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativePaginateOperation {
  const _MatrixNativePaginateOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
  });

  final String libraryPath;
  final int address;
  final String roomId;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final paginate = library
        .lookupFunction<_ClientPaginateNative, _ClientPaginateDart>(
          'kite_matrix_client_paginate_backwards',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final value = paginate(
        Pointer<Void>.fromAddress(address),
        roomIdUtf8.cast<Char>(),
      );
      if (value == nullptr) {
        throw StateError('Matrix Rust SDK back-pagination failed');
      }
      try {
        final payload = value.cast<Utf8>().toDartString();
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error'];
          if (error is String) {
            throw StateError('Matrix Rust SDK back-pagination failed: $error');
          }
        }
        return payload;
      } finally {
        freeString(value);
      }
    } finally {
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeSyncDecodeOperation {
  const _MatrixNativeSyncDecodeOperation(this.payload);

  final String payload;

  MatrixRustSyncDecodeResult call() {
    return MatrixRustSyncCodec().decodeSync(payload);
  }
}

final class _MatrixNativePaginationDecodeOperation {
  const _MatrixNativePaginationDecodeOperation(this.payload);

  final String payload;

  MatrixRustPaginationDecodeResult call() {
    return MatrixRustSyncCodec().decodePagination(payload);
  }
}

abstract interface class MatrixRustCodecExecutor {
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload);

  Future<MatrixRustPaginationDecodeResult> decodePagination(String payload);
}

final class IsolateMatrixRustCodecExecutor implements MatrixRustCodecExecutor {
  const IsolateMatrixRustCodecExecutor();

  @override
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload) {
    return Isolate.run<MatrixRustSyncDecodeResult>(
      _MatrixNativeSyncDecodeOperation(payload).call,
    );
  }

  @override
  Future<MatrixRustPaginationDecodeResult> decodePagination(String payload) {
    return Isolate.run<MatrixRustPaginationDecodeResult>(
      _MatrixNativePaginationDecodeOperation(payload).call,
    );
  }
}

final class _MatrixNativeFreeOperation {
  const _MatrixNativeFreeOperation({
    required this.libraryPath,
    required this.address,
  });

  final String libraryPath;
  final int address;

  void call() {
    final library = DynamicLibrary.open(libraryPath);
    final clientFree = library
        .lookupFunction<_ClientFreeNative, _ClientFreeDart>(
          'kite_matrix_client_free',
        );
    clientFree(Pointer<Void>.fromAddress(address));
  }
}

abstract interface class MatrixRustAuthenticationBridge {
  Future<MatrixRustAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  );
}

abstract interface class MatrixRustSessionClient {
  Future<MatrixRustSessionDescriptor?> restoreSession();

  Future<void> persistSession();
}

abstract interface class MatrixRustBridge {
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  });
}

abstract interface class MatrixRustRoomMembersClient {
  Future<List<MatrixRustRoomMember>> roomMembers({required String roomId});
}

abstract interface class MatrixRustClient {
  bool get isClosed;

  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  });

  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  });

  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  });

  Future<String> paginateBackwards({required String roomId});

  Future<void> close();
}

final class MatrixRustNativeBridge
    implements MatrixRustBridge, MatrixRustAuthenticationBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

  @override
  Future<MatrixRustAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    final homeserverText = homeserver.toString().trim();
    if (homeserverText.isEmpty || homeserverText.contains('\u0000')) {
      throw ArgumentError.value(
        homeserver,
        'homeserver',
        'must not be empty or contain NUL bytes',
      );
    }
    final payload = await Isolate.run<String>(
      _MatrixNativeDiscoverAuthenticationOperation(
        libraryPath: libraryPath,
        homeserver: homeserverText,
      ).call,
    );
    final value = _decodeNativeEnvelope(payload);
    if (value is! Map<String, dynamic>) {
      throw const MatrixRustNativeException(
        code: 'invalid_native_response',
        publicMessage:
            'The Matrix native bridge returned invalid discovery data.',
      );
    }
    final discoveredHomeserver = value['homeserver'];
    final passwordAvailable = value['password'];
    final parsedHomeserver = discoveredHomeserver is String
        ? Uri.tryParse(discoveredHomeserver)
        : null;
    if (parsedHomeserver == null ||
        !parsedHomeserver.hasScheme ||
        passwordAvailable is! bool) {
      throw const MatrixRustNativeException(
        code: 'invalid_native_response',
        publicMessage:
            'The Matrix native bridge returned invalid discovery data.',
      );
    }
    return MatrixRustAuthenticationDiscovery(
      homeserver: parsedHomeserver,
      passwordAvailable: passwordAvailable,
    );
  }

  @override
  Future<MatrixRustNativeClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  }) async {
    if (storePath.trim().isEmpty) {
      throw ArgumentError.value(storePath, 'storePath', 'must not be empty');
    }
    if (storePassphrase.isEmpty) {
      throw ArgumentError.value(
        storePassphrase,
        'storePassphrase',
        'must not be empty',
      );
    }
    if (storePath.contains('\u0000')) {
      throw ArgumentError.value(
        storePath,
        'storePath',
        'must not contain NUL bytes',
      );
    }
    if (storePassphrase.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'storePassphrase',
        'must not contain NUL bytes',
      );
    }

    final path = libraryPath;
    final homeserverText = homeserver.toString();
    final address = await Isolate.run<int>(() {
      final library = DynamicLibrary.open(path);
      final abiVersion = library
          .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
            'kite_matrix_abi_version',
          );
      if (abiVersion() != kiteMatrixNativeAbiVersion) {
        throw StateError('Unsupported Kite Matrix native ABI');
      }

      final clientNew = library
          .lookupFunction<_ClientNewNative, _ClientNewDart>(
            'kite_matrix_client_new',
          );
      final homeserverUtf8 = homeserverText.toNativeUtf8(allocator: calloc);
      final storePathUtf8 = storePath.toNativeUtf8(allocator: calloc);
      final passphraseUtf8 = storePassphrase.toNativeUtf8(allocator: calloc);
      final passphraseBytePointer = passphraseUtf8.cast<Uint8>();
      var passphraseByteLength = 0;
      while (passphraseBytePointer[passphraseByteLength] != 0) {
        passphraseByteLength += 1;
      }
      final passphraseBytes = passphraseBytePointer.asTypedList(
        passphraseByteLength + 1,
      );
      try {
        final client = clientNew(
          homeserverUtf8.cast<Char>(),
          storePathUtf8.cast<Char>(),
          passphraseUtf8.cast<Char>(),
        );
        if (client == nullptr) {
          throw StateError(
            'Matrix Rust SDK encrypted client construction failed',
          );
        }
        return client.address;
      } finally {
        passphraseBytes.fillRange(0, passphraseBytes.length, 0);
        calloc.free(passphraseUtf8);
        calloc.free(storePathUtf8);
        calloc.free(homeserverUtf8);
      }
    });

    return MatrixRustNativeClient._(libraryPath, address);
  }
}

final class MatrixRustNativeClient
    implements
        MatrixRustClient,
        MatrixRustSessionClient,
        MatrixRustRoomMembersClient {
  MatrixRustNativeClient._(this.libraryPath, this._address);

  final String libraryPath;
  int _address;
  Future<void> _transition = Future<void>.value();

  @override
  bool get isClosed => _address == 0;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || normalizedUsername.contains('\u0000')) {
      return Future<MatrixRustLoginResult>.error(
        ArgumentError.value(
          username,
          'username',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (password.isEmpty || password.contains('\u0000')) {
      return Future<MatrixRustLoginResult>.error(
        ArgumentError.value(
          '<redacted>',
          'password',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<MatrixRustLoginResult>(() async {
      final payload = await Isolate.run<String>(
        _MatrixNativeLoginPasswordOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          username: normalizedUsername,
          password: password,
        ).call,
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid login data.',
        );
      }
      final userId = decoded['userId'];
      final deviceId = decoded['deviceId'];
      if (userId is! String ||
          userId.isEmpty ||
          deviceId is! String ||
          deviceId.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid login data.',
        );
      }
      return MatrixRustLoginResult(userId: userId, deviceId: deviceId);
    });
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedTransactionId = transactionId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedTransactionId.isEmpty ||
        normalizedTransactionId.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          transactionId,
          'transactionId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (body.isEmpty || body.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          body.isEmpty ? body : '<redacted>',
          'body',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<MatrixRustSendResult>(() async {
      final payload = await Isolate.run<String>(
        _MatrixNativeSendTextOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          transactionId: normalizedTransactionId,
          body: body,
        ).call,
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid send data.',
        );
      }
      final eventId = decoded['eventId'];
      if (eventId is! String || eventId.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid send data.',
        );
      }
      return MatrixRustSendResult(eventId: eventId);
    });
  }

  @override
  Future<MatrixRustSessionDescriptor?> restoreSession() {
    return _enqueue<MatrixRustSessionDescriptor?>(() async {
      final payload = await Isolate.run<String>(
        _MatrixNativeSessionOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          symbol: 'kite_matrix_client_restore_session',
          operation: 'session restore',
        ).call,
      );
      final value = _decodeNativeEnvelope(payload);
      return value == null ? null : _decodeSessionDescriptor(value);
    });
  }

  @override
  Future<void> persistSession() {
    return _enqueue<void>(() async {
      final payload = await Isolate.run<String>(
        _MatrixNativeSessionOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          symbol: 'kite_matrix_client_persist_session',
          operation: 'session persistence',
        ).call,
      );
      _decodeNativeEnvelope(payload);
    });
  }

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) {
    if (timeout.isNegative) {
      return Future<String>.error(
        ArgumentError.value(timeout, 'timeout', 'must not be negative'),
      );
    }
    if (timelineEventLimit <= 0) {
      return Future<String>.error(
        ArgumentError.value(
          timelineEventLimit,
          'timelineEventLimit',
          'must be positive',
        ),
      );
    }
    if (since != null && (since.isEmpty || since.contains('\u0000'))) {
      return Future<String>.error(
        ArgumentError.value(
          since,
          'since',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<String>(() async {
      final address = _requireAddress();
      final path = libraryPath;
      final timeoutMs = timeout.inMilliseconds;
      return Isolate.run<String>(
        _MatrixNativeSyncOperation(
          libraryPath: path,
          address: address,
          timeoutMs: timeoutMs,
          since: since,
          timelineEventLimit: timelineEventLimit,
        ).call,
      );
    });
  }

  @override
  Future<List<MatrixRustRoomMember>> roomMembers({required String roomId}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<List<MatrixRustRoomMember>>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<List<MatrixRustRoomMember>>(() async {
      final decoded = await Isolate.run<Map<String, Object?>>(
        _MatrixNativeRoomMembersOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
        ).call,
      );
      if (decoded['roomId'] != normalizedRoomId ||
          decoded['members'] is! List) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room member data.',
        );
      }
      final members = <MatrixRustRoomMember>[];
      for (final value in decoded['members'] as List) {
        if (value is! Map<String, dynamic>) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage:
                'The Matrix native bridge returned invalid room member data.',
          );
        }
        final userId = value['userId'];
        final displayName = value['displayName'];
        final powerLevel = value['powerLevel'];
        if (userId is! String ||
            userId.isEmpty ||
            displayName is! String ||
            displayName.isEmpty ||
            powerLevel is! int) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage:
                'The Matrix native bridge returned invalid room member data.',
          );
        }
        members.add(
          MatrixRustRoomMember(
            userId: userId,
            displayName: displayName,
            powerLevel: powerLevel,
          ),
        );
      }
      return List<MatrixRustRoomMember>.unmodifiable(members);
    });
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<String>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<String>(() async {
      final address = _requireAddress();
      final path = libraryPath;
      return Isolate.run<String>(
        _MatrixNativePaginateOperation(
          libraryPath: path,
          address: address,
          roomId: normalizedRoomId,
        ).call,
      );
    });
  }

  @override
  Future<void> close() {
    return _enqueue<void>(() async {
      if (_address == 0) return;
      final address = _address;
      final path = libraryPath;
      await Isolate.run<void>(
        _MatrixNativeFreeOperation(libraryPath: path, address: address).call,
      );
      _address = 0;
    });
  }

  int _requireAddress() {
    final address = _address;
    if (address == 0) {
      throw StateError('Matrix Rust SDK client is closed');
    }
    return address;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _transition.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace _) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }
}

final class MatrixRustSdkBoundary
    implements
        MatrixSdkBoundary,
        MatrixSdkPasswordAuthenticator,
        MatrixSdkTextMessageSender,
        MatrixSdkRoomMemberDirectory {
  MatrixRustSdkBoundary({
    required this.bridge,
    required this.homeserver,
    required this.resolveStoreSecret,
    MatrixRustCodecExecutor? codecExecutor,
    MatrixRustSyncDelay? syncRetryDelay,
    this.logger,
    this.crashReporter,
  }) : _codecExecutor = codecExecutor ?? const IsolateMatrixRustCodecExecutor(),
       _syncRetryDelay = syncRetryDelay ?? Future<void>.delayed;

  final MatrixRustBridge bridge;
  final Uri homeserver;
  final MatrixSdkStoreSecretResolver resolveStoreSecret;
  final MatrixRustCodecExecutor _codecExecutor;
  final MatrixRustSyncDelay _syncRetryDelay;
  final StructuredLogger? logger;
  final CrashReporter? crashReporter;
  final StreamController<MatrixSyncBatch> _syncBatches =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixRustClient? _client;
  MatrixSdkStoreConfiguration? _openedStore;
  Future<void> _transition = Future<void>.value();
  Future<void>? _syncLoop;
  Completer<void>? _retryWakeup;
  bool _syncRequested = false;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.incrementalSync,
    MatrixSdkCapability.backPagination,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches => _syncBatches.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) {
    return _enqueue(() async {
      final client = _client;
      if (client != null) {
        final openedStore = _openedStore;
        if (openedStore == null || !_sameStore(openedStore, store)) {
          throw StateError(
            'Matrix Rust SDK boundary is already open for another store',
          );
        }
        return;
      }
      final storeSecret = await resolveStoreSecret(store.encryptionKeyId);
      if (storeSecret.isEmpty) {
        throw StateError(
          'Matrix SDK store secret resolver returned an empty secret',
        );
      }
      if (storeSecret.contains('\u0000')) {
        throw ArgumentError.value(
          '<redacted>',
          'storeSecret',
          'must not contain NUL bytes',
        );
      }
      _client = await bridge.openEncryptedClient(
        homeserver: homeserver,
        storePath: store.storePath,
        storePassphrase: storeSecret,
      );
      _openedStore = store;
    });
  }

  @override
  Future<MatrixSdkPasswordLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    return _enqueue<MatrixSdkPasswordLoginResult>(() async {
      final result = await _requireClient().loginWithPassword(
        username: username,
        password: password,
      );
      return MatrixSdkPasswordLoginResult(
        userId: result.userId,
        deviceId: result.deviceId,
      );
    });
  }

  @override
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
  }) {
    return _enqueue<String>(() async {
      final result = await _requireClient().sendText(
        roomId: roomId,
        transactionId: transactionId,
        body: body,
      );
      return result.eventId;
    });
  }

  @override
  Future<List<MatrixSdkRoomMember>> roomMembers(String roomId) {
    return _enqueue<List<MatrixSdkRoomMember>>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomMembersClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room member lookup',
        );
      }
      final memberClient = client as MatrixRustRoomMembersClient;
      final members = await memberClient.roomMembers(roomId: roomId);
      return List<MatrixSdkRoomMember>.unmodifiable(
        members.map(
          (member) => MatrixSdkRoomMember(
            userId: member.userId,
            displayName: member.displayName,
            powerLevel: member.powerLevel,
          ),
        ),
      );
    });
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) {
    return _enqueue(() async {
      if (configuration.initialRoomListLimit <= 0 ||
          configuration.initialTimelineEventLimit <= 0 ||
          configuration.timelineEventLimit <= 0 ||
          configuration.initialTimelineEventLimit >
              configuration.timelineEventLimit ||
          configuration.resumeFromCursor?.isEmpty == true ||
          configuration.resumeFromCursor?.contains('\u0000') == true) {
        throw ArgumentError.value(
          configuration,
          'configuration',
          'contains invalid Matrix sync limits or resume cursor',
        );
      }
      if (_syncLoop != null) return;
      final client = _requireClient();
      _syncRequested = true;
      late final Future<void> loop;
      loop = _runSyncLoop(client, configuration).whenComplete(() {
        if (identical(_syncLoop, loop)) {
          _syncLoop = null;
        }
      });
      _syncLoop = loop;
      unawaited(loop);
    });
  }

  @override
  Future<void> stopSync() {
    return _enqueue(_stopSync);
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) {
    return _enqueue<MatrixPaginationPage>(() async {
      final trace = logger?.trace(
        DiagnosticFlow.timeline,
        DiagnosticOperation.timelineUpdate,
      );
      trace?.log(LogLevel.info, DiagnosticEvent.started);
      try {
        final normalizedRoomId = roomId.trim();
        if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
          throw ArgumentError.value(
            roomId,
            'roomId',
            'must not be empty or contain NUL bytes',
          );
        }
        final payload = await _requireClient().paginateBackwards(
          roomId: normalizedRoomId,
        );
        final decoded = await _codecExecutor.decodePagination(payload);
        if (decoded.roomId != normalizedRoomId) {
          throw StateError('Matrix Rust SDK pagination room mismatch');
        }
        trace?.log(
          LogLevel.info,
          DiagnosticEvent.completed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.itemCount: decoded.events.length,
          },
        );
        return MatrixPaginationPage(
          roomId: decoded.roomId,
          events: decoded.events,
          reachedStart: decoded.reachedStart,
        );
      } catch (error, stackTrace) {
        trace?.log(LogLevel.error, DiagnosticEvent.failed);
        _reportFailure(
          error,
          stackTrace,
          trace,
          flow: DiagnosticFlow.timeline,
          operation: DiagnosticOperation.timelineUpdate,
          state: CrashState.active,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  @override
  Future<void> close() {
    return _enqueue(() async {
      await _stopSync();
      final client = _client;
      if (client == null) return;
      await client.close();
      if (identical(_client, client)) {
        _client = null;
        _openedStore = null;
      }
    });
  }

  Future<void> _runSyncLoop(
    MatrixRustClient client,
    MatrixSdkSyncConfiguration configuration,
  ) async {
    var firstRequest = true;
    var failureAttempt = 0;
    var syncToken = configuration.resumeFromCursor;
    while (_syncRequested && identical(_client, client)) {
      final trace = logger?.trace(
        DiagnosticFlow.sync,
        DiagnosticOperation.syncCycle,
      );
      trace?.log(LogLevel.info, DiagnosticEvent.started);
      try {
        final isColdRequest = firstRequest && syncToken == null;
        final payload = await client.syncOnce(
          timeout: firstRequest ? Duration.zero : _matrixRustSyncPollTimeout,
          timelineEventLimit: isColdRequest
              ? configuration.initialTimelineEventLimit
              : configuration.timelineEventLimit,
          since: syncToken,
        );
        if (!_syncRequested || !identical(_client, client)) return;
        final syncFailure = _decodeMatrixRustSyncFailure(payload);
        if (syncFailure != null) {
          if (syncFailure.code == _MatrixRustSyncFailureCode.unknownPosition &&
              syncToken != null) {
            syncToken = null;
            failureAttempt = 0;
            continue;
          }
          throw syncFailure;
        }
        final decoded = await _codecExecutor.decodeSync(payload);
        trace?.log(
          LogLevel.info,
          DiagnosticEvent.completed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.itemCount: decoded.batch.rooms.length,
          },
        );
        final fullyPublished = await _publishSyncBatch(
          decoded.batch,
          roomChunkSize: isColdRequest
              ? configuration.initialRoomListLimit
              : null,
        );
        if (!fullyPublished) return;
        syncToken = decoded.batch.cursor;
        firstRequest = false;
        failureAttempt = 0;
      } catch (error, stackTrace) {
        if (!_syncRequested || !identical(_client, client)) return;
        failureAttempt += 1;
        final isPermanentPayloadFailure =
            error is FormatException ||
            (error is _MatrixRustSyncFailure && error.isPermanent);
        trace?.log(
          LogLevel.error,
          DiagnosticEvent.failed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.attempt: failureAttempt,
          },
        );
        _reportFailure(
          error,
          stackTrace,
          trace,
          flow: DiagnosticFlow.sync,
          operation: DiagnosticOperation.syncCycle,
          state: isPermanentPayloadFailure
              ? CrashState.active
              : CrashState.retrying,
        );
        final syncError =
            error is _MatrixRustSyncFailure && error.isSessionExpired
            ? const MatrixSessionExpiredException()
            : error;
        _syncBatches.addError(
          isPermanentPayloadFailure
              ? MatrixNonRetryableSyncException(syncError)
              : syncError,
          stackTrace,
        );
        if (isPermanentPayloadFailure) {
          _syncRequested = false;
          return;
        }
        await _waitForRetry(_matrixRustRetryDelayForAttempt(failureAttempt));
      }
    }
  }

  Future<bool> _publishSyncBatch(
    MatrixSyncBatch syncBatch, {
    required int? roomChunkSize,
  }) async {
    if (roomChunkSize == null || syncBatch.rooms.length <= roomChunkSize) {
      _syncBatches.add(syncBatch);
      return true;
    }

    for (
      var start = 0;
      start < syncBatch.rooms.length;
      start += roomChunkSize
    ) {
      if (!_syncRequested) return false;
      final end = start + roomChunkSize < syncBatch.rooms.length
          ? start + roomChunkSize
          : syncBatch.rooms.length;
      final isFinalChunk = end == syncBatch.rooms.length;
      _syncBatches.add(
        MatrixSyncBatch(
          cursor: syncBatch.cursor,
          rooms: List<MatrixRoomDelta>.unmodifiable(
            syncBatch.rooms.sublist(start, end),
          ),
          commitCursor: isFinalChunk,
        ),
      );
      if (!isFinalChunk) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return true;
  }

  void _reportFailure(
    Object error,
    StackTrace stackTrace,
    TraceLogger? trace, {
    required DiagnosticFlow flow,
    required DiagnosticOperation operation,
    required CrashState state,
  }) {
    final reporter = crashReporter;
    if (reporter == null || trace == null) return;
    try {
      final report = reporter.report(
        error,
        stackTrace: stackTrace,
        context: CrashDiagnosticContext(
          flow: flow,
          traceId: trace.traceId,
          operation: operation,
          component: CrashComponent.matrixSdk,
          state: state,
        ),
      );
      unawaited(report.catchError((Object _, StackTrace _) {}));
    } catch (_) {}
  }

  Future<void> _waitForRetry(Duration duration) async {
    final wakeup = Completer<void>();
    _retryWakeup = wakeup;
    try {
      if (!_syncRequested) return;
      await Future.any<void>(<Future<void>>[
        _syncRetryDelay(duration),
        wakeup.future,
      ]);
    } finally {
      if (identical(_retryWakeup, wakeup)) {
        _retryWakeup = null;
      }
    }
  }

  Future<void> _stopSync() async {
    _syncRequested = false;
    final wakeup = _retryWakeup;
    if (wakeup != null && !wakeup.isCompleted) {
      wakeup.complete();
    }
    final loop = _syncLoop;
    if (loop != null) {
      await loop;
      if (identical(_syncLoop, loop)) {
        _syncLoop = null;
      }
    }
  }

  static bool _sameStore(
    MatrixSdkStoreConfiguration left,
    MatrixSdkStoreConfiguration right,
  ) {
    return left.accountId == right.accountId &&
        left.storePath == right.storePath &&
        left.encryptionKeyId == right.encryptionKeyId;
  }

  MatrixRustClient _requireClient() {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('Matrix Rust SDK client is not open');
    }
    return client;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _transition.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace _) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }
}
