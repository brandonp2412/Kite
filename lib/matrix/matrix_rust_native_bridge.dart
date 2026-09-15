import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

const int kiteMatrixNativeAbiVersion = 3;

const Duration _matrixRustSyncPollTimeout = Duration(seconds: 5);

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
typedef _ClientSyncOnceNative = Pointer<Char> Function(Pointer<Void>, Uint64);
typedef _ClientSyncOnceDart = Pointer<Char> Function(Pointer<Void>, int);
typedef _ClientPaginateNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _ClientPaginateDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _StringFreeNative = Void Function(Pointer<Char> value);
typedef _StringFreeDart = void Function(Pointer<Char> value);
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

typedef MatrixSdkStoreSecretResolver = Future<String> Function(String keyId);
typedef MatrixRustSyncDelay = Future<void> Function(Duration duration);

final class _MatrixNativeSyncOperation {
  const _MatrixNativeSyncOperation({
    required this.libraryPath,
    required this.address,
    required this.timeoutMs,
  });

  final String libraryPath;
  final int address;
  final int timeoutMs;

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
    final value = syncOnce(Pointer<Void>.fromAddress(address), timeoutMs);
    if (value == nullptr) {
      throw StateError('Matrix Rust SDK sync failed');
    }
    try {
      return value.cast<Utf8>().toDartString();
    } finally {
      freeString(value);
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
        return value.cast<Utf8>().toDartString();
      } finally {
        freeString(value);
      }
    } finally {
      calloc.free(roomIdUtf8);
    }
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

abstract interface class MatrixRustBridge {
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  });
}

abstract interface class MatrixRustClient {
  bool get isClosed;

  Future<String> syncOnce({required Duration timeout});

  Future<String> paginateBackwards({required String roomId});

  Future<void> close();
}

final class MatrixRustNativeBridge implements MatrixRustBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

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

final class MatrixRustNativeClient implements MatrixRustClient {
  MatrixRustNativeClient._(this.libraryPath, this._address);

  final String libraryPath;
  int _address;
  Future<void> _transition = Future<void>.value();

  @override
  bool get isClosed => _address == 0;

  @override
  Future<String> syncOnce({required Duration timeout}) {
    if (timeout.isNegative) {
      return Future<String>.error(
        ArgumentError.value(timeout, 'timeout', 'must not be negative'),
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
        ).call,
      );
    });
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    if (roomId.trim().isEmpty) {
      return Future<String>.error(
        ArgumentError.value(roomId, 'roomId', 'must not be empty'),
      );
    }
    return _enqueue<String>(() async {
      final address = _requireAddress();
      final path = libraryPath;
      return Isolate.run<String>(
        _MatrixNativePaginateOperation(
          libraryPath: path,
          address: address,
          roomId: roomId,
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

final class MatrixRustSdkBoundary implements MatrixSdkBoundary {
  MatrixRustSdkBoundary({
    required this.bridge,
    required this.homeserver,
    required this.resolveStoreSecret,
    MatrixRustSyncCodec? codec,
    MatrixRustSyncDelay? syncRetryDelay,
  }) : _codec = codec ?? MatrixRustSyncCodec(),
       _syncRetryDelay = syncRetryDelay ?? Future<void>.delayed;

  final MatrixRustBridge bridge;
  final Uri homeserver;
  final MatrixSdkStoreSecretResolver resolveStoreSecret;
  final MatrixRustSyncCodec _codec;
  final MatrixRustSyncDelay _syncRetryDelay;
  final StreamController<MatrixSyncBatch> _syncBatches =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixRustClient? _client;
  Future<void> _transition = Future<void>.value();
  Future<void>? _syncLoop;
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
      if (_client != null) return;
      final storeSecret = await resolveStoreSecret(store.encryptionKeyId);
      if (storeSecret.isEmpty) {
        throw StateError(
          'Matrix SDK store secret resolver returned an empty secret',
        );
      }
      _client = await bridge.openEncryptedClient(
        homeserver: homeserver,
        storePath: store.storePath,
        storePassphrase: storeSecret,
      );
    });
  }

  @override
  Future<void> startSync() {
    return _enqueue(() async {
      if (_syncLoop != null) return;
      final client = _requireClient();
      _syncRequested = true;
      late final Future<void> loop;
      loop = _runSyncLoop(client).whenComplete(() {
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
      final normalizedRoomId = roomId.trim();
      if (normalizedRoomId.isEmpty) {
        throw ArgumentError.value(roomId, 'roomId', 'must not be empty');
      }
      final payload = await _requireClient().paginateBackwards(
        roomId: normalizedRoomId,
      );
      final decoded = _codec.decodePagination(payload);
      if (decoded.roomId != normalizedRoomId) {
        throw StateError('Matrix Rust SDK pagination room mismatch');
      }
      return MatrixPaginationPage(
        roomId: decoded.roomId,
        events: decoded.events,
        reachedStart: decoded.reachedStart,
      );
    });
  }

  @override
  Future<void> close() {
    return _enqueue(() async {
      await _stopSync();
      final client = _client;
      _client = null;
      await client?.close();
    });
  }

  Future<void> _runSyncLoop(MatrixRustClient client) async {
    var firstRequest = true;
    while (_syncRequested && identical(_client, client)) {
      try {
        final payload = await client.syncOnce(
          timeout: firstRequest ? Duration.zero : _matrixRustSyncPollTimeout,
        );
        if (!_syncRequested || !identical(_client, client)) return;
        final decoded = _codec.decodeSync(payload);
        _syncBatches.add(decoded.batch);
        firstRequest = false;
      } catch (error, stackTrace) {
        if (!_syncRequested || !identical(_client, client)) return;
        _syncBatches.addError(error, stackTrace);
        await _syncRetryDelay(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _stopSync() async {
    _syncRequested = false;
    final loop = _syncLoop;
    if (loop != null) {
      await loop;
      if (identical(_syncLoop, loop)) {
        _syncLoop = null;
      }
    }
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
