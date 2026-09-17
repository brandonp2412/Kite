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
      expect(restored.invites, hasLength(1));
      expect(restored.invites.single.roomId, '!invite:example.org');
      expect(restored.invites.single.roomName, 'Persisted invite');
      expect(restored.invites.single.inviterDisplayName, 'Bob');
      expect(restored.invites.single.memberCount, 7);
      expect(restored.rooms, hasLength(1));
      expect(restored.rooms.single.roomId, '!room:example.org');
      expect(restored.rooms.single.displayName, 'Persisted room');
      expect(restored.rooms.single.unreadCount, 3);
      expect(restored.rooms.single.highlightCount, 2);
      expect(restored.rooms.single.hasActiveCall, isTrue);
      expect(restored.rooms.single.isFavourite, isTrue);
      expect(restored.rooms.single.isMuted, isTrue);
      expect(restored.timelines['!room:example.org'], hasLength(1));
      final event = restored.timelines['!room:example.org']!.single;
      expect(event.eventId, r'$event:example.org');
      expect(event.senderDisplayName, 'Alice');
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

    test(
      'recovers the last good snapshot after an interrupted replace',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kite-presentation-recovery-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final store = FileMatrixPresentationStore(directory);
        const accountId = '@alice:example.org';
        await store.save(accountId, _snapshot(cursor: 'before-crash'));

        final accountDirectory = Directory(
          '${directory.path}/${Uri.encodeComponent(accountId)}',
        );
        final file = File('${accountDirectory.path}/presentation.json');
        await file.rename('${file.path}.bak');
        await File('${file.path}.tmp').writeAsString('{interrupted');

        expect((await store.load(accountId))?.syncCursor, 'before-crash');

        await store.save(accountId, _snapshot(cursor: 'after-recovery'));
        expect((await store.load(accountId))?.syncCursor, 'after-recovery');
        expect(await File('${file.path}.bak').exists(), isFalse);
        expect(await File('${file.path}.tmp').exists(), isFalse);

        await file.copy('${file.path}.bak');
        await File('${file.path}.tmp').writeAsString('{stale');
        await store.clear(accountId);
        expect(await store.load(accountId), isNull);
        expect(await file.exists(), isFalse);
        expect(await File('${file.path}.bak').exists(), isFalse);
        expect(await File('${file.path}.tmp').exists(), isFalse);
      },
    );

    test('falls back to a valid backup when the primary snapshot is corrupt', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-backup-fallback-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileMatrixPresentationStore(directory);
      const accountId = '@alice:example.org';
      await store.save(accountId, _snapshot(cursor: 'backup-good'));

      final file = File(
        '${directory.path}/${Uri.encodeComponent(accountId)}/presentation.json',
      );
      await file.copy('${file.path}.bak');
      await file.writeAsString('{corrupt-primary');

      expect((await store.load(accountId))?.syncCursor, 'backup-good');
    });

    test('falls back when a syntactically valid primary has invalid date ranges', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-range-fallback-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileMatrixPresentationStore(directory);
      const accountId = '@alice:example.org';
      await store.save(accountId, _snapshot(cursor: 'range-backup'));

      final file = File(
        '${directory.path}/${Uri.encodeComponent(accountId)}/presentation.json',
      );
      await file.copy('${file.path}.bak');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'syncCursor': 'invalid-primary',
          'rooms': <Object?>[
            <String, Object?>{
              'roomId': '!room:example.org',
              'displayName': 'Invalid timestamp',
              'lastActivityMs': 9223372036854775807,
              'streamPosition': 1,
              'unreadCount': 0,
            },
          ],
          'timelines': <String, Object?>{},
        }),
      );

      expect((await store.load(accountId))?.syncCursor, 'range-backup');
    });

    test('rejects cross-room timeline data from persisted snapshots', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-cross-room-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      const accountId = '@alice:example.org';
      final accountDirectory = Directory(
        '${directory.path}/${Uri.encodeComponent(accountId)}',
      );
      await accountDirectory.create(recursive: true);
      await File('${accountDirectory.path}/presentation.json').writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'syncCursor': 'must-not-resume',
          'rooms': <Object?>[
            <String, Object?>{
              'roomId': '!alpha:example.org',
              'displayName': 'Alpha',
              'lastActivityMs': 1,
              'streamPosition': 1,
              'unreadCount': 0,
            },
          ],
          'timelines': <String, Object?>{
            '!alpha:example.org': <Object?>[
              <String, Object?>{
                'eventId': r'$wrong-room',
                'roomId': '!beta:example.org',
                'senderId': '@bob:example.org',
                'type': 'm.room.message',
                'originServerTimestampMs': 1,
                'streamPosition': 1,
                'content': <String, Object?>{'body': 'must not leak'},
              },
            ],
          },
        }),
      );

      expect(
        await FileMatrixPresentationStore(directory).load(accountId),
        isNull,
      );
    });

    test('rejects an empty persisted sync cursor', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-presentation-empty-cursor-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      const accountId = '@alice:example.org';
      final accountDirectory = Directory(
        '${directory.path}/${Uri.encodeComponent(accountId)}',
      );
      await accountDirectory.create(recursive: true);
      await File('${accountDirectory.path}/presentation.json').writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'syncCursor': '',
          'rooms': <Object?>[],
          'timelines': <String, Object?>{},
        }),
      );

      expect(
        await FileMatrixPresentationStore(directory).load(accountId),
        isNull,
      );
    });

    test(
      'rejects unsafe account ids before touching presentation files',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kite-presentation-account-id-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final store = FileMatrixPresentationStore(directory);

        await expectLater(
          store.load('@alice:example.org\u0000other'),
          throwsArgumentError,
        );
        await expectLater(
          store.save('@alice:example.org\u0000other', _snapshot()),
          throwsArgumentError,
        );
        expect(await directory.exists(), isTrue);
        expect(await directory.list().isEmpty, isTrue);
      },
    );

    test(
      'rejects persisted snapshots containing NUL Matrix identifiers',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kite-presentation-nul-id-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        const accountId = '@alice:example.org';
        final accountDirectory = Directory(
          '${directory.path}/${Uri.encodeComponent(accountId)}',
        );
        await accountDirectory.create(recursive: true);
        await File('${accountDirectory.path}/presentation.json').writeAsString(
          jsonEncode(<String, Object?>{
            'version': 1,
            'syncCursor': 'safe-cursor',
            'rooms': <Object?>[
              <String, Object?>{
                'roomId': '!room:example.org\u0000other',
                'displayName': 'Unsafe room',
                'lastActivityMs': 1,
                'streamPosition': 1,
                'unreadCount': 0,
              },
            ],
            'timelines': <String, Object?>{},
          }),
        );

        expect(
          await FileMatrixPresentationStore(directory).load(accountId),
          isNull,
        );
      },
    );

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
    invites: const <MatrixRoomInvite>[
      MatrixRoomInvite(
        roomId: '!invite:example.org',
        roomName: 'Persisted invite',
        inviterId: '@bob:example.org',
        inviterDisplayName: 'Bob',
        memberCount: 7,
        description: 'Cached before reconnect',
      ),
    ],
    rooms: <MatrixRoomSummary>[
      MatrixRoomSummary(
        roomId: '!room:example.org',
        displayName: 'Persisted room',
        lastActivity: DateTime.utc(2026, 9, 15, 4, 30),
        streamPosition: 42,
        lastEventId: r'$event:example.org',
        unreadCount: 3,
        highlightCount: 2,
        hasActiveCall: true,
        isFavourite: true,
        isMuted: true,
      ),
    ],
    timelines: <String, List<MatrixTimelineEvent>>{
      '!room:example.org': <MatrixTimelineEvent>[
        MatrixTimelineEvent(
          eventId: r'$event:example.org',
          roomId: '!room:example.org',
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          type: 'm.room.message',
          originServerTimestamp: DateTime.utc(2026, 9, 15, 4, 29),
          streamPosition: 42,
          content: <String, Object?>{'body': 'offline-first'},
        ),
      ],
    },
  );
}
