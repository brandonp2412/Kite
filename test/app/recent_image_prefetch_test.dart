import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/recent_image_prefetch.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  test('warms newest images in recent rooms and continues after 12 images', () {
    final prefetch = RecentImagePrefetch();
    final initial = snapshot();
    final images = prefetch.pending(initial);
    expect(images, hasLength(12));
    expect(images.first.uri, 'mxc://test/0-2');
    expect(images.any((image) => image.uri == 'mxc://test/6-2'), isFalse);
    expect(prefetch.pending(initial), isEmpty);

    final updated = snapshot(offset: 10);
    expect(prefetch.pending(updated), hasLength(12));
    expect(prefetch.pending(updated), isEmpty);
  });

  test('preserves encrypted sources and skips redacted images', () {
    final initial = snapshot();
    final events = initial.timelines['room0']!;
    final encrypted = events.last.copyWith(
      content: {
        'msgtype': 'm.image',
        'file': {
          'url': 'mxc://test/encrypted',
          'key': {'k': 'secret'},
        },
      },
    );
    final updated = MatrixPresentationSnapshot(
      rooms: initial.rooms.take(1).toList(),
      timelines: {
        'room0': [events.first, encrypted, events[1].copyWith(redacted: true)],
      },
    );
    final images = RecentImagePrefetch().pending(updated);
    expect(images.map((image) => image.uri), [
      'mxc://test/encrypted',
      'mxc://test/0-0',
    ]);
    expect(images.first.encryptedFile, encrypted.content['file']);
  });

  test('failed images can retry and activation resets the window', () {
    final prefetch = RecentImagePrefetch();
    final initial = snapshot();
    final uri = prefetch.pending(initial).first.uri;
    prefetch.retry(uri);
    expect(prefetch.pending(initial).single.uri, uri);
    prefetch.clear();
    expect(prefetch.pending(initial), hasLength(12));
  });
}

MatrixPresentationSnapshot snapshot({int offset = 0}) {
  return MatrixPresentationSnapshot(
    rooms: [
      for (var room = 0; room < 7; room++)
        MatrixRoomSummary(
          roomId: 'room$room',
          displayName: 'Room $room',
          lastActivity: DateTime(2026),
          streamPosition: 7 - room,
        ),
    ],
    timelines: {
      for (var room = 0; room < 7; room++)
        'room$room': [
          for (var event = 0; event < 3; event++)
            MatrixTimelineEvent(
              eventId: 'event$room-${event + offset}',
              roomId: 'room$room',
              senderId: '@me:test',
              type: 'm.room.message',
              originServerTimestamp: DateTime(2026),
              streamPosition: event + offset,
              content: {
                'msgtype': 'm.image',
                'url': 'mxc://test/$room-${event + offset}',
              },
            ),
        ],
    },
  );
}
