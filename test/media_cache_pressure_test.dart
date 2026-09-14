import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/media/media_cache_policy.dart';

void main() {
  testWidgets('decoded media cache stays inside the Kite pressure envelope', (
    tester,
  ) async {
    final cache = PaintingBinding.instance.imageCache;
    final previousMaximumSize = cache.maximumSize;
    final previousMaximumSizeBytes = cache.maximumSizeBytes;
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
      cache.maximumSize = previousMaximumSize;
      cache.maximumSizeBytes = previousMaximumSizeBytes;
    });

    cache.clear();
    cache.clearLiveImages();
    KiteMediaCachePolicy.apply(cache);

    expect(cache.maximumSize, KiteMediaCachePolicy.maximumDecodedImages);
    expect(cache.maximumSizeBytes, KiteMediaCachePolicy.maximumDecodedBytes);

    BuildContext? context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    const imageDimension = 1024;
    const imageCount = 12;
    final providers = List<_PressureImageProvider>.generate(
      imageCount,
      (index) => _PressureImageProvider(index, imageDimension),
      growable: false,
    );

    for (final provider in providers) {
      await precacheImage(provider, context!);
      await tester.pump();
      expect(
        cache.currentSizeBytes,
        lessThanOrEqualTo(KiteMediaCachePolicy.maximumDecodedBytes),
      );
      expect(
        cache.currentSize,
        lessThanOrEqualTo(KiteMediaCachePolicy.maximumDecodedImages),
      );
    }

    expect(cache.currentSize, lessThan(imageCount));
    expect(
      cache.currentSizeBytes,
      lessThanOrEqualTo(KiteMediaCachePolicy.maximumDecodedBytes),
    );

    final oldestStatus = cache.statusForKey(providers.first.cacheKey);
    final newestStatus = cache.statusForKey(providers.last.cacheKey);
    expect(oldestStatus.keepAlive, isFalse);
    expect(newestStatus.keepAlive, isTrue);
  });
}

final class _PressureImageProvider extends ImageProvider<int> {
  const _PressureImageProvider(this.cacheKey, this.dimension);

  final int cacheKey;
  final int dimension;

  @override
  Future<int> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<int>(cacheKey);
  }

  @override
  ImageStreamCompleter loadImage(int key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_createImageInfo(key));
  }

  Future<ImageInfo> _createImageInfo(int key) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = ui.Color(0xFF000000 | ((key * 0x00123457) & 0x00FFFFFF));
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, dimension.toDouble(), dimension.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(dimension, dimension);
    picture.dispose();
    return ImageInfo(image: image, scale: 1);
  }
}
