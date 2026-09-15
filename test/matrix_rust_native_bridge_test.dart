import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

void main() {
  final libraryPath = Platform.environment['KITE_MATRIX_BRIDGE_LIBRARY'];

  test('native boundary advertises only implemented SDK capabilities', () {
    final boundary = MatrixRustSdkBoundary(
      bridge: const MatrixRustNativeBridge(libraryPath: '/not-opened'),
      homeserver: Uri.parse('https://matrix.example.org'),
      resolveStoreSecret: (_) async => 'unused',
    );

    expect(boundary.capabilities, <MatrixSdkCapability>{
      MatrixSdkCapability.auditedEncryption,
      MatrixSdkCapability.encryptedPersistentStore,
    });
    expect(
      () => MatrixBoundaryEngine(
        boundary: boundary,
        store: const MatrixSdkStoreConfiguration(
          accountId: '@alice:example.org',
          storePath: '/tmp/kite/alice',
          encryptionKeyId: 'alice-key',
        ),
      ),
      throwsA(isA<MatrixSdkContractException>()),
    );
  });

  test('native bridge rejects an empty store passphrase before FFI', () async {
    final bridge = MatrixRustNativeBridge(
      libraryPath: libraryPath ?? '/unused',
    );

    await expectLater(
      bridge.openEncryptedClient(
        homeserver: Uri.parse('https://matrix.example.org'),
        storePath: '/tmp/kite/alice',
        storePassphrase: '',
      ),
      throwsArgumentError,
    );
  });

  test(
    'SDK boundary coalesces concurrent opens and close waits for opening',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'kite-matrix-boundary-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      var secretResolutions = 0;
      final boundary = MatrixRustSdkBoundary(
        bridge: MatrixRustNativeBridge(libraryPath: libraryPath!),
        homeserver: Uri.parse('http://localhost:8008'),
        resolveStoreSecret: (_) async {
          secretResolutions += 1;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'deterministic-boundary-secret';
        },
      );
      final store = MatrixSdkStoreConfiguration(
        accountId: '@alice:example.org',
        storePath: '${temp.path}/matrix-sdk',
        encryptionKeyId: 'alice-key',
      );

      final firstOpen = boundary.open(store);
      final secondOpen = boundary.open(store);
      final closing = boundary.close();
      await Future.wait<void>(<Future<void>>[firstOpen, secondOpen, closing]);
      expect(secretResolutions, 1);

      await boundary.open(store);
      expect(secretResolutions, 2);
      await boundary.close();
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );

  test(
    'Dart opens and closes a passphrase-encrypted Matrix Rust SDK store off-isolate',
    () async {
      final temp = await Directory.systemTemp.createTemp('kite-matrix-ffi-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final storePath = '${temp.path}/matrix-sdk';
      final bridge = MatrixRustNativeBridge(libraryPath: libraryPath!);

      final client = await bridge.openEncryptedClient(
        homeserver: Uri.parse('http://localhost:8008'),
        storePath: storePath,
        storePassphrase: 'deterministic-🔐-store-secret',
      );

      expect(client.isClosed, isFalse);
      expect(await Directory(storePath).exists(), isTrue);
      await client.close();
      await client.close();
      expect(client.isClosed, isTrue);
    },
    skip: libraryPath == null
        ? 'Set KITE_MATRIX_BRIDGE_LIBRARY after building the Rust bridge.'
        : false,
  );
}
