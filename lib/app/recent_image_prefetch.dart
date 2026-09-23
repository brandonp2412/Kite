import 'package:kite/matrix/matrix_models.dart';

typedef RecentImage = ({String uri, Map<String, Object?>? encryptedFile});

/// Tracks a rolling window, rather than a lifetime quota of warmed images.
final class RecentImagePrefetch {
  final Set<String> _scheduled = {};

  List<RecentImage> pending(MatrixPresentationSnapshot snapshot) {
    final candidates = <String, RecentImage>{};
    for (final room in snapshot.rooms.take(6)) {
      var count = 0;
      for (final event
          in (snapshot.timelines[room.roomId] ?? const <MatrixTimelineEvent>[])
              .reversed) {
        if (event.redacted || event.content['msgtype'] != 'm.image') continue;
        final file = event.content['file'];
        final encryptedFile = file is Map<String, Object?> ? file : null;
        final uri = encryptedFile?['url'] ?? event.content['url'];
        if (uri is! String || !uri.startsWith('mxc://')) continue;
        candidates[uri] = (uri: uri, encryptedFile: encryptedFile);
        if (++count == 2) break;
      }
    }
    _scheduled.retainAll(candidates.keys);
    return [
      for (final image in candidates.values)
        if (_scheduled.add(image.uri)) image,
    ];
  }

  void retry(String uri) => _scheduled.remove(uri);

  void clear() => _scheduled.clear();
}
