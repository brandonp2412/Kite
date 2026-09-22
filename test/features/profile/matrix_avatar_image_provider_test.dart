import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/profile/matrix_avatar_image_provider.dart';

void main() {
  testWidgets(
    'Matrix avatar provider loads media and participates in image cache',
    (tester) async {
      var loads = 0;
      final namespace = Object();
      final provider = MatrixAvatarImageProvider(
        avatarUri: Uri.parse('mxc://example.org/avatar'),
        cacheNamespace: namespace,
        loadBytes: (_) async {
          loads += 1;
          return _onePixelPng;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                Image(image: provider, width: 48, height: 48),
                Image(image: provider, width: 48, height: 48),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guarded prefetch absorbs Matrix media load failures', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final provider = MatrixAvatarImageProvider(
      avatarUri: Uri.parse('mxc://example.org/missing-avatar'),
      cacheNamespace: Object(),
      loadBytes: (_) => Future<Uint8List>.error(
        StateError('Cannot download Matrix media for an inactive account'),
      ),
    );

    expect(await precacheMatrixImage(provider, context), isFalse);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('cache identity includes runtime namespace', () {
    final uri = Uri.parse('mxc://example.org/avatar');
    final namespace = Object();
    Future<Uint8List> loader(Uri _) async => _onePixelPng;
    final first = MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: namespace,
      loadBytes: loader,
    );
    final sameRuntime = MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: namespace,
      loadBytes: loader,
    );
    final differentRuntime = MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: Object(),
      loadBytes: loader,
    );
    final differentVariant = MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: namespace,
      cacheVariant: 'full',
      loadBytes: loader,
    );
    final differentDecodeSize = MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: namespace,
      cacheWidth: 720,
      cacheHeight: 720,
      loadBytes: loader,
    );

    expect(first, sameRuntime);
    expect(first.hashCode, sameRuntime.hashCode);
    expect(first, isNot(differentRuntime));
    expect(first, isNot(differentVariant));
    expect(first, isNot(differentDecodeSize));
  });
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
