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
      for (final crate in <String>[
        'vodozemac',
        'olm-rs',
        'matrix-sdk-crypto',
      ]) {
        expect(
          RegExp('^$crate\\s*=\\s*', multiLine: true).hasMatch(cargo),
          isFalse,
          reason: '$crate must not bypass the audited Matrix SDK boundary',
        );
      }
    },
  );

  test('production Dart code does not use synchronous filesystem APIs', () {
    final forbidden = RegExp(
      r'\b(?:readAsBytesSync|readAsStringSync|writeAsBytesSync|writeAsStringSync|openSync|copySync|renameSync|deleteSync|createSync)\s*\(',
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
        'lib/matrix/matrix_restoration.dart',
        'lib/matrix/matrix_rust_sync_codec.dart',
        'lib/matrix/presentation_store.dart',
      ]);

      for (final path in <String>[
        'lib/matrix/matrix_restoration.dart',
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
