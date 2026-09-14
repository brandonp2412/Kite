import 'package:flutter/painting.dart';

final class KiteMediaCachePolicy {
  const KiteMediaCachePolicy._();

  static const int maximumDecodedImages = 96;
  static const int maximumDecodedBytes = 32 * 1024 * 1024;

  static void apply([ImageCache? cache]) {
    final target = cache ?? PaintingBinding.instance.imageCache;
    target.maximumSize = maximumDecodedImages;
    target.maximumSizeBytes = maximumDecodedBytes;
  }
}
