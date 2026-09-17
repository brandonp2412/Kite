import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

typedef MatrixMediaBytesLoader = Future<Uint8List> Function(Uri contentUri);

@immutable
final class MatrixAvatarImageProvider
    extends ImageProvider<MatrixAvatarImageProvider> {
  const MatrixAvatarImageProvider({
    required this.avatarUri,
    required this.cacheNamespace,
    required this.loadBytes,
  });

  final Uri avatarUri;
  final Object cacheNamespace;
  final MatrixMediaBytesLoader loadBytes;

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
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) {
    return other is MatrixAvatarImageProvider &&
        other.avatarUri == avatarUri &&
        identical(other.cacheNamespace, cacheNamespace);
  }

  @override
  int get hashCode => Object.hash(avatarUri, identityHashCode(cacheNamespace));
}
