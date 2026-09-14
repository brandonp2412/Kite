import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

const int kiteMatrixNativeAbiVersion = 1;

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _ClientNewNative = Pointer<Void> Function(Pointer<Char> homeserver);
typedef _ClientNewDart = Pointer<Void> Function(Pointer<Char> homeserver);
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

/// Executable low-level Dart -> Rust Matrix SDK boundary.
///
/// The production session worker will keep the native handle on a dedicated
/// isolate. This class intentionally exposes only an off-isolate smoke/open
/// check so no blocking Rust SDK construction can accidentally run on the
/// Flutter UI isolate while the higher-level session worker is built out.
final class MatrixRustNativeBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

  Future<void> verifyClientConstruction(Uri homeserver) {
    final path = libraryPath;
    final homeserverText = homeserver.toString();
    return Isolate.run<void>(() {
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
      final clientFree = library
          .lookupFunction<_ClientFreeNative, _ClientFreeDart>(
            'kite_matrix_client_free',
          );
      final homeserverUtf8 = homeserverText.toNativeUtf8(allocator: calloc);
      Pointer<Void> client;
      try {
        client = clientNew(homeserverUtf8.cast<Char>());
      } finally {
        calloc.free(homeserverUtf8);
      }
      if (client == nullptr) {
        throw StateError('Matrix Rust SDK client construction failed');
      }

      clientFree(client);
    });
  }
}
