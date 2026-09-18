import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'state routing and Matrix crypto dependencies stay within contracts',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final cargo = File('rust/kite_matrix_bridge/Cargo.toml')
          .readAsStringSync();

      for (final package in <String>[
        'flutter_riverpod',
        'hooks_riverpod',
        'riverpod',
        'go_router',
        'crypto',
        'cryptography',
        'pointycastle',
      ]) {
        expect(
          RegExp('^\\s*$package\\s*:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: '$package must not become a direct Flutter dependency',
        );
      }

      expect(
        RegExp(r'^matrix-sdk\s*=\s*', multiLine: true).hasMatch(cargo),
        isTrue,
        reason:
            'Matrix cryptography and encrypted storage must stay in matrix-sdk',
      );
      for (final crate in <String>['vodozemac', 'olm-rs']) {
        expect(
          RegExp('^$crate\\s*=\\s*', multiLine: true).hasMatch(cargo),
          isFalse,
          reason: '$crate must not bypass the audited Matrix SDK boundary',
        );
      }

      expect(
        RegExp(
          r'^matrix-sdk-crypto\s*=\s*"0\.18\.0"\s*$',
          multiLine: true,
        ).hasMatch(cargo),
        isTrue,
        reason: 'Legacy backup-key recovery may use only the Matrix SDK crypto crate version matched to matrix-sdk',
      );
      final bridgeSource = File('rust/kite_matrix_bridge/src/lib.rs')
          .readAsStringSync();
      expect(
        RegExp(
          r'use matrix_sdk_crypto::\{store::types::BackupDecryptionKey, types::RoomKeyBackupInfo\};',
        ).allMatches(bridgeSource).length,
        1,
        reason: 'The direct Matrix crypto dependency is restricted to legacy backup-key recovery types',
      );
      expect(
        RegExp(r'\bmatrix_sdk_crypto::').allMatches(bridgeSource).length,
        1,
        reason: 'Matrix crypto access outside the audited legacy backup-key adapter is forbidden',
      );
    },
  );

  test('production Dart code does not use synchronous filesystem APIs', () {
    final forbidden = RegExp(
      r'\b(?:readAsBytesSync|readAsStringSync|readAsLinesSync|writeAsBytesSync|writeAsStringSync|openSync|copySync|renameSync|deleteSync|createSync|existsSync|statSync|listSync|createTempSync|resolveSymbolicLinksSync|setLastModifiedSync|lastModifiedSync)\s*\(',
    );

    for (final file in _dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      expect(
        forbidden.hasMatch(source),
        isFalse,
        reason: '${file.path} performs blocking filesystem work',
      );
    }
  });

  test(
    'production JSON parsing is restricted to background-isolated adapters',
    () {
      final jsonFiles = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        if (source.contains('jsonDecode(') || source.contains('jsonEncode(')) {
          jsonFiles.add(file.path);
        }
      }
      jsonFiles.sort();

      expect(jsonFiles, <String>[
        'lib/matrix/io_matrix_well_known_client.dart',
        'lib/matrix/matrix_restoration.dart',
        'lib/matrix/matrix_rust_auth_session_api.dart',
        'lib/matrix/matrix_rust_native_bridge.dart',
        'lib/matrix/matrix_rust_sync_codec.dart',
        'lib/matrix/presentation_store.dart',
      ]);

      for (final path in <String>[
        'lib/matrix/io_matrix_well_known_client.dart',
        'lib/matrix/matrix_restoration.dart',
        'lib/matrix/matrix_rust_auth_session_api.dart',
        'lib/matrix/matrix_rust_native_bridge.dart',
        'lib/matrix/presentation_store.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('Isolate.run'),
          reason: '$path must keep JSON work off the UI isolate',
        );
      }

      final codecImports = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.path.endsWith('matrix_rust_sync_codec.dart')) continue;
        if (file.readAsStringSync().contains('matrix_rust_sync_codec.dart')) {
          codecImports.add(file.path);
        }
      }
      codecImports.sort();
      expect(codecImports, <String>[
        'lib/matrix/matrix_rust_native_bridge.dart',
      ]);

      final nativeBridge = File('lib/matrix/matrix_rust_native_bridge.dart')
          .readAsStringSync();
      expect(nativeBridge, contains('IsolateMatrixRustCodecExecutor'));
      expect(
        RegExp(r'Isolate\.run<MatrixRustSyncDecodeResult>')
            .hasMatch(nativeBridge),
        isTrue,
      );
      expect(
        RegExp(r'Isolate\.run<MatrixRustPaginationDecodeResult>')
            .hasMatch(nativeBridge),
        isTrue,
      );
    },
  );

  test('Matrix sync callbacks do not eagerly clone the presentation cache', () {
    final source = File('lib/matrix/matrix_account_runtime_registry.dart')
        .readAsStringSync();
    final callbacks = RegExp(
      r'applyBatch: \(batch\) \{([\s\S]*?)\},\s*applyPagination: \(page\) \{([\s\S]*?)\},',
    ).firstMatch(source);

    expect(callbacks, isNotNull);
    expect(callbacks!.group(1), isNot(contains('snapshot()')));
    expect(callbacks.group(2), isNot(contains('snapshot()')));
    expect(source, contains('_schedulePresentationWrite(accountId, cache)'));
    expect(source, contains('final snapshot = cache.snapshot('));
    expect(source, contains('roomLimit: presentationRoomLimit'));
    expect(
      source,
      contains('timelineEventLimitPerRoom: presentationTimelineEventLimit'),
    );
  });

  test('Matrix native FFI operations stay off the Flutter UI isolate', () {
    final nativeBridge = File('lib/matrix/matrix_rust_native_bridge.dart')
        .readAsStringSync();

    expect(
      nativeBridge,
      contains('final address = await Isolate.run<int>(() {'),
    );
    for (final operation in <String>[
      '_MatrixNativeSyncOperation',
      '_MatrixNativePaginateOperation',
      '_MatrixNativeFreeOperation',
    ]) {
      expect(
        RegExp('Isolate\\.run<[^>]+>\\(\\s*$operation\\(')
            .hasMatch(nativeBridge),
        isTrue,
        reason: '$operation must execute through Isolate.run',
      );
    }
  });
}

Iterable<File> _dartFilesUnder(String path) sync* {
  final entities = Directory(path)
      .listSync(recursive: true, followLinks: false);
  for (final entity in entities) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
