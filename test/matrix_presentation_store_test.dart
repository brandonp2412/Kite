import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_store.dart';

void main() {
  group('FileMatrixPresentationStore', () {
    test('round-trips room, timeline, and sync cursor state', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-store-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileMatrixPresentationStore(directory);
      final snapshot = _snapshot();

      await store.save('@alice:example.org', snapshot);
      final restored = await store.load('@alice:example.org');

      expect(restored, isNotNull);
      expect(restored!.syncCursor, 'sync-42');
      expect(restored.rooms, hasLength(1));
      expect(restored.rooms.single.roomId, '!room:example.org');
      expect(restored.rooms.single.displayName, 'Persisted room');
      expect(restored.rooms.single.unreadCount, 3);
      expect(restored.timelines['!room:example.org'], hasLength(1));
      final event = restored.timelines['!room:example.org']!.single;
      expect(event.eventId, r'$event:example.org');
      expect(event.content, <String, Object?>{'body': 'offline-first'});
    });

    test('isolates presentation files by account', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-isolation-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileMatrixPresentationStore(directory);

      await store.save('@alice:example.org', _snapshot(cursor: 'alice'));
      await store.save('@bob:example.org', _snapshot(cursor: 'bob'));

      expect((await store.load('@alice:example.org'))?.syncCursor, 'alice');
      expect((await store.load('@bob:example.org'))?.syncCursor, 'bob');
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.endsWith('presentation.json')),
        hasLength(2),
      );
    });

    test('ignores malformed persisted snapshots', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-malformed-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final accountDirectory = Directory(
        '${directory.path}/${Uri.encodeComponent('@alice:example.org')}',
      );
      await accountDirectory.create(recursive: true);
      await File('${accountDirectory.path}/presentation.json').writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'rooms': <Object?>[
            <String, Object?>{'roomId': '!missing-fields:example.org'},
          ],
          'timelines': <String, Object?>{},
        }),
      );

      expect(
        await FileMatrixPresentationStore(directory).load('@alice:example.org'),
        isNull,
      );
    });
  });
}

MatrixPresentationSnapshot _snapshot({String cursor = 'sync-42'}) {
  return MatrixPresentationSnapshot(
    syncCursor: cursor,
    rooms: <MatrixRoomSummary>[
      MatrixRoomSummary(
        roomId: '!room:example.org',
        displayName: 'Persisted room',
        lastActivity: DateTime.utc(2026, 9, 15, 4, 30),
        streamPosition: 42,
        lastEventId: r'$event:example.org',
        unreadCount: 3,
      ),
    ],
    timelines: <String, List<MatrixTimelineEvent>>{
      '!room:example.org': <MatrixTimelineEvent>[
        MatrixTimelineEvent(
          eventId: r'$event:example.org',
          roomId: '!room:example.org',
          senderId: '@alice:example.org',
          type: 'm.room.message',
          originServerTimestamp: DateTime.utc(2026, 9, 15, 4, 29),
          streamPosition: 42,
          content: <String, Object?>{'body': 'offline-first'},
        ),
      ],
    },
  );
}
