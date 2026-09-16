import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final mainSource = File('lib/main.dart').readAsStringSync();
  final runtimeSource = File(
    'lib/app/production_kite_runtime.dart',
  ).readAsStringSync();
  final homeSource = File(
    'lib/features/home/matrix_home_presentation.dart',
  ).readAsStringSync();

  test('production startup composes native Matrix authentication', () {
    expect(mainSource, contains('ProductionKiteRuntime.create()'));
    expect(runtimeSource, contains('MatrixRustNativeBridge('));
    expect(runtimeSource, contains('MatrixRustAuthSessionApi('));
    expect(runtimeSource, contains('NativeMatrixAccountSdkBoundary(authApi)'));
    expect(runtimeSource, contains('accountSdkBoundary: widget.accountBoundary'));
    expect(runtimeSource, contains('authenticatedHomeBuilder:'));
  });

  test('production rooms and timeline come only from the Matrix cache', () {
    expect(runtimeSource, contains('return MatrixHomeScreen('));
    expect(runtimeSource, contains('cache: cache'));
    expect(homeSource, contains('roomListStore: _binding.roomListStore'));
    expect(homeSource, contains('timeline: _binding.controller'));
    expect(homeSource, contains('fixtureProvider: (_) => const []'));
    expect(homeSource, isNot(contains('BenchmarkFixture')));
  });

  test('production composer injects the real Matrix text sender', () {
    expect(runtimeSource, contains('sendPort: MatrixTimelineSendPort('));
    expect(runtimeSource, contains('widget.runtime.sendTextMessage('));
    expect(homeSource, contains('required this.sendPort'));
    expect(homeSource, contains('sendPort: sendPort'));
    expect(
      homeSource,
      isNot(contains('DeterministicTimelineSendPort')),
      reason:
          'The production Matrix presentation adapter must never select the deterministic sender.',
    );
  });
}
