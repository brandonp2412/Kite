import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';

void main() {
  final libraryPath = Platform.environment['KITE_MATRIX_BRIDGE_LIBRARY'];

  test(
    'Dart can construct and release a Matrix Rust SDK client off-isolate',
    () async {
      final bridge = MatrixRustNativeBridge(libraryPath: libraryPath!);

      await bridge.verifyClientConstruction(Uri.parse('http://localhost:8008'));
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );
}
