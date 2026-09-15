import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

const int kiteMatrixNativeAbiVersion = 2;

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
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

typedef MatrixSdkStoreSecretResolver = Future<String> Function(String keyId);

final class MatrixRustNativeBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

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

final class MatrixRustNativeClient {
  MatrixRustNativeClient._(this.libraryPath, this._address);

  final String libraryPath;
  int _address;
  Future<void>? _closing;

  bool get isClosed => _address == 0;

  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    if (_address == 0) return Future<void>.value();

    final address = _address;
    late final Future<void> closing;
    closing =
        Isolate.run<void>(() {
              final library = DynamicLibrary.open(libraryPath);
              final clientFree = library
                  .lookupFunction<_ClientFreeNative, _ClientFreeDart>(
                    'kite_matrix_client_free',
                  );
              clientFree(Pointer<Void>.fromAddress(address));
            })
            .then<void>((_) {
              _address = 0;
            })
            .whenComplete(() {
              if (_address != 0 && identical(_closing, closing)) {
                _closing = null;
              }
            });
    _closing = closing;
    return closing;
  }
}

final class MatrixRustSdkBoundary implements MatrixSdkBoundary {
  MatrixRustSdkBoundary({
    required this.bridge,
    required this.homeserver,
    required this.resolveStoreSecret,
  });

  final MatrixRustNativeBridge bridge;
  final Uri homeserver;
  final MatrixSdkStoreSecretResolver resolveStoreSecret;

  MatrixRustNativeClient? _client;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches =>
      const Stream<MatrixSyncBatch>.empty();

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
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
  }

  @override
  Future<void> startSync() {
    throw UnsupportedError(
      'Matrix Rust SDK sync is not exposed by the native boundary yet',
    );
  }

  @override
  Future<void> stopSync() async {}

  @override
  Future<void> paginateBackwards(String roomId) {
    throw UnsupportedError(
      'Matrix Rust SDK back-pagination is not exposed by the native boundary yet',
    );
  }

  @override
  Future<void> close() async {
    final client = _client;
    _client = null;
    await client?.close();
  }
}
