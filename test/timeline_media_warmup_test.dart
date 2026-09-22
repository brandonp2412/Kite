import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/timeline/timeline_media_warmup.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  test('warms newest image from each recent room before second images', () {
    final snapshot = MatrixPresentationSnapshot(
      rooms: <MatrixRoomSummary>[
        _room('recent', 30),
        _room('middle', 20),
        _room('old', 10),
      ],
      timelines: <String, List<MatrixTimelineEvent>>{
        'recent': <MatrixTimelineEvent>[
          _image('recent', 'recent-old', 1),
          _image('recent', 'recent-new', 2),
        ],
        'middle': <MatrixTimelineEvent>[
          _image('middle', 'middle-old', 1),
          _image('middle', 'middle-new', 2),
        ],
        'old': <MatrixTimelineEvent>[_image('old', 'old-new', 1)],
      },
    );

    final selected = selectRecentTimelineImageWarmups(
      snapshot: snapshot,
      currentUserId: '@me:example.org',
      roomLimit: 3,
      perRoomLimit: 2,
      totalLimit: 5,
    );

    expect(selected.map((attachment) => attachment.contentUri), <String>[
      'mxc://example.org/recent-new',
      'mxc://example.org/middle-new',
      'mxc://example.org/old-new',
      'mxc://example.org/recent-old',
      'mxc://example.org/middle-old',
    ]);
  });

  test('includes encrypted recent images and ignores non-image messages', () {
    final snapshot = MatrixPresentationSnapshot(
      rooms: <MatrixRoomSummary>[_room('recent', 30)],
      timelines: <String, List<MatrixTimelineEvent>>{
        'recent': <MatrixTimelineEvent>[
          _text('recent', 'hello', 1),
          _encryptedImage('recent', 'secret', 2),
        ],
      },
    );

    final selected = selectRecentTimelineImageWarmups(
      snapshot: snapshot,
      currentUserId: '@me:example.org',
    );

    expect(selected, hasLength(1));
    expect(selected.single.contentUri, 'mxc://example.org/secret');
    expect(selected.single.encryptedFile?['url'], 'mxc://example.org/secret');
  });
}

MatrixRoomSummary _room(String roomId, int activity) {
  return MatrixRoomSummary(
    roomId: roomId,
    displayName: roomId,
    lastActivity: DateTime.fromMillisecondsSinceEpoch(activity, isUtc: true),
    streamPosition: activity,
  );
}

MatrixTimelineEvent _image(String roomId, String id, int position) {
  return _event(roomId, id, position, <String, Object?>{
    'msgtype': 'm.image',
    'body': '$id.jpg',
    'url': 'mxc://example.org/$id',
  });
}

MatrixTimelineEvent _encryptedImage(String roomId, String id, int position) {
  return _event(roomId, id, position, <String, Object?>{
    'msgtype': 'm.image',
    'body': '$id.jpg',
    'file': <String, Object?>{
      'url': 'mxc://example.org/$id',
      'v': 'v2',
      'iv': 'fixture-iv',
      'key': <String, Object?>{'kty': 'oct', 'k': 'fixture-key'},
      'hashes': <String, Object?>{'sha256': 'fixture-hash'},
    },
  });
}

MatrixTimelineEvent _text(String roomId, String body, int position) {
  return _event(roomId, 'text-$position', position, <String, Object?>{
    'msgtype': 'm.text',
    'body': body,
  });
}

MatrixTimelineEvent _event(
  String roomId,
  String id,
  int position,
  Map<String, Object?> content,
) {
  return MatrixTimelineEvent(
    eventId: '\$$id',
    roomId: roomId,
    senderId: '@alice:example.org',
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 23, 8, position),
    streamPosition: position,
    content: content,
  );
}
