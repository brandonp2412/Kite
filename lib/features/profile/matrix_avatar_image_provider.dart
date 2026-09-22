import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef MatrixMediaBytesLoader = Future<Uint8List> Function(Uri contentUri);

Future<bool> precacheMatrixImage(
  ImageProvider<Object> provider,
  BuildContext context,
) async {
  var failed = false;
  try {
    await precacheImage(
      provider,
      context,
      onError: (_, _) {
        failed = true;
      },
    );
  } catch (_) {
    return false;
  }
  return !failed;
}

@immutable
final class MatrixAvatarImageProvider
    extends ImageProvider<MatrixAvatarImageProvider> {
  const MatrixAvatarImageProvider({
    required this.avatarUri,
    required this.cacheNamespace,
    required this.loadBytes,
    this.cacheVariant,
    this.cacheWidth,
    this.cacheHeight,
  });

  final Uri avatarUri;
  final Object cacheNamespace;
  final MatrixMediaBytesLoader loadBytes;
  final Object? cacheVariant;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Future<MatrixAvatarImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<MatrixAvatarImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    MatrixAvatarImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: avatarUri.toString(),
    );
  }

  Future<ui.Codec> _loadAsync(
    MatrixAvatarImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await loadBytes(avatarUri);
    if (bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('Matrix avatar media is empty');
    }
    final targetWidth = cacheWidth;
    final targetHeight = cacheHeight;
    if (targetWidth != null || targetHeight != null) {
      return ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) {
    return other is MatrixAvatarImageProvider &&
        other.avatarUri == avatarUri &&
        identical(other.cacheNamespace, cacheNamespace) &&
        other.cacheVariant == cacheVariant &&
        other.cacheWidth == cacheWidth &&
        other.cacheHeight == cacheHeight;
  }

  @override
  int get hashCode => Object.hash(
    avatarUri,
    identityHashCode(cacheNamespace),
    cacheVariant,
    cacheWidth,
    cacheHeight,
  );
}
