// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/widgets/mxc_image.dart';
import 'package:matrix/matrix.dart';

class _ImageDatabase implements DatabaseApi {
  _ImageDatabase(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List?> getFile(Uri uri) async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('static avatars build one placeholder without a cross-fade', (
    tester,
  ) async {
    final client = Client(
      'placeholder test',
      database: _ImageDatabase(Uint8List(0)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MxcImage(
          client: client,
          width: 48,
          height: 48,
          animationDuration: Duration.zero,
          placeholder: (_) => const Text('AB'),
        ),
      ),
    );
    expect(find.text('AB'), findsOneWidget);
    expect(find.byType(AnimatedCrossFade), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('thumbnail decoding bounds pixels and preserves aspect ratio', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1600, 800);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    }))!;
    final client = Client('image test', database: _ImageDatabase(bytes));
    client.homeserver = Uri.parse('https://example.test');

    Future<void> pumpImage({bool thumbnail = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: MxcImage(
              key: ValueKey(thumbnail),
              client: client,
              uri: Uri.parse('mxc://example.test/image'),
              width: 48,
              height: 48,
              isThumbnail: thumbnail,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await pumpImage();
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 144);
    expect(provider.height, 144);
    expect(provider.policy, ResizeImagePolicy.fit);

    final decoded = await tester.runAsync(() async {
      final stream = provider.resolve(ImageConfiguration.empty);
      final result = Completer<(int, int)>();
      final listener = ImageStreamListener((info, _) {
        result.complete((info.image.width, info.image.height));
        info.dispose();
      }, onError: result.completeError);
      stream.addListener(listener);
      try {
        return await result.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    });
    expect(decoded, (144, 72));

    await pumpImage(thumbnail: false);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
