import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';

void main() {
  test('native auth errors keep public detail out of diagnostics', () {
    const error = MatrixRustNativeException(
      code: 'authentication_rejected',
      publicMessage: 'Matrix login was rejected.',
    );

    expect(error.code, 'authentication_rejected');
    expect(error.publicMessage, 'Matrix login was rejected.');
    expect(error.toString(), contains('authentication_rejected'));
    expect(error.toString(), isNot(contains('Matrix login was rejected.')));
  });

  test('native auth/session ABI revision is pinned', () {
    expect(kiteMatrixNativeAbiVersion, 9);
  });
}
