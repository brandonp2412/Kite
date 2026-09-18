import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('async feature signal owners declare an unmount lifecycle guard', () {
    final violations = <String>[];

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final ownsSignals =
          source.contains('signal<') || source.contains('signal(');
      final hasAsyncWork =
          source.contains(' async {') || source.contains('await ');
      final hasDispose = source.contains('void dispose()');

      if (!ownsSignals || !hasAsyncWork || !hasDispose) continue;

      final guarded =
          source.contains('AsyncControllerLifecycle') ||
          source.contains('_accountGeneration') ||
          source.contains('_loadGeneration') ||
          source.contains('_searchGeneration') ||
          source.contains('mounted');

      if (!guarded) {
        violations.add(entity.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Async signal owners must invalidate pending work before disposal, '
          'or use Flutter mounted checks. Unguarded owners: $violations',
    );
  });
}
