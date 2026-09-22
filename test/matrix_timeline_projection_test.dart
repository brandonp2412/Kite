import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';

void main() {
  test(
    'Matrix room projection exposes latest sender, preview and unread count',
    () {
      final cache = MatrixPresentationCache();
      cache.applySync(
        MatrixSyncBatch(
          cursor: 's1',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!alpha:example.org',
              summary: MatrixRoomSummary(
                roomId: '!alpha:example.org',
                displayName: 'Alpha',
                lastActivity: DateTime.utc(2026, 9, 16, 10, 30),
                streamPosition: 1,
                lastEventId: r'$one',
                unreadCount: 3,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                _event(
                  eventId: r'$one',
                  streamPosition: 1,
                  senderId: '@alice:example.org',
                  senderDisplayName: 'Alice',
                  msgtype: 'm.text',
                  body: 'Synced from Matrix',
                ),
              ],
            ),
          ],
        ),
      );

      final entries = matrixRoomListEntries(cache);

      expect(entries, hasLength(1));
      expect(entries.single.id, '!alpha:example.org');
      expect(entries.single.name, 'Alpha');
      expect(entries.single.latestSender, 'Alice');
      expect(entries.single.latestEventBody, 'Synced from Matrix');
      expect(entries.single.unreadCount, 3);
    },
  );

  test('Matrix room projection keeps the newest message preview when state follows it', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:example.org',
            summary: MatrixRoomSummary(
              roomId: '!alpha:example.org',
              displayName: 'Alpha',
              lastActivity: DateTime.utc(2026, 9, 16, 10, 31),
              streamPosition: 2,
              lastEventId: r'$membership',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$message',
                streamPosition: 1,
                senderId: '@alice:example.org',
                senderDisplayName: 'Alice',
                msgtype: 'm.text',
                body: 'Newest useful message',
              ),
              MatrixTimelineEvent(
                eventId: r'$membership',
                roomId: '!alpha:example.org',
                senderId: '@alice:example.org',
                type: 'm.room.member',
                originServerTimestamp: DateTime.utc(2026, 9, 16, 10, 31),
                streamPosition: 2,
                content: const <String, Object?>{'membership': 'join'},
              ),
            ],
          ),
        ],
      ),
    );

    final entry = matrixRoomListEntries(cache).single;

    expect(entry.latestSender, 'Alice');
    expect(entry.latestEventBody, 'Newest useful message');
  });

  test('Matrix room projection labels undecryptable encrypted messages', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:example.org',
            summary: MatrixRoomSummary(
              roomId: '!alpha:example.org',
              displayName: 'Alpha',
              lastActivity: DateTime.utc(2026, 9, 16, 10, 31),
              streamPosition: 1,
              lastEventId: r'$encrypted',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              MatrixTimelineEvent(
                eventId: r'$encrypted',
                roomId: '!alpha:example.org',
                senderId: '@alice:example.org',
                senderDisplayName: 'Alice',
                type: 'm.room.encrypted',
                originServerTimestamp: DateTime.utc(2026, 9, 16, 10, 31),
                streamPosition: 1,
                content: const <String, Object?>{
                  'algorithm': 'm.megolm.v1.aes-sha2',
                  'ciphertext': '<redacted>',
                },
              ),
            ],
          ),
        ],
      ),
    );

    final entry = matrixRoomListEntries(cache).single;

    expect(entry.latestSender, 'Alice');
    expect(entry.latestEventBody, 'Unable to decrypt message');
  });

  test('Matrix room projection uses event-aware media previews', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:example.org',
            summary: MatrixRoomSummary(
              roomId: '!alpha:example.org',
              displayName: 'Alpha',
              lastActivity: DateTime.utc(2026, 9, 16, 10, 30),
              streamPosition: 1,
              lastEventId: r'$image',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$image',
                streamPosition: 1,
                senderId: '@alice:example.org',
                senderDisplayName: 'Alice',
                msgtype: 'm.image',
                body: 'IMG_0042.jpg',
              ),
            ],
          ),
        ],
      ),
    );

    final entry = matrixRoomListEntries(cache).single;

    expect(entry.latestSender, 'Alice');
    expect(entry.latestEventBody, 'Image');
  });

  test(
    'Matrix media projection preserves image sources and sender avatars',
    () {
      final plain = TimelineMessage.fromMatrixEvent(
        _event(
          eventId: r'$plain-image',
          streamPosition: 1,
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          senderAvatarUrl: 'mxc://example.org/alice-avatar',
          msgtype: 'm.image',
          body: 'photo.jpg',
          extra: const <String, Object?>{
            'url': 'mxc://example.org/plain-image',
          },
        ),
        currentUserId: '@me:example.org',
      );
      expect(plain, isNotNull);
      expect(plain!.senderAvatarUrl, 'mxc://example.org/alice-avatar');
      expect(plain.attachment!.contentUri, 'mxc://example.org/plain-image');
      expect(plain.attachment!.encryptedFile, isNull);

      final encrypted = TimelineMessage.fromMatrixEvent(
        _event(
          eventId: r'$encrypted-image',
          streamPosition: 2,
          senderId: '@alice:example.org',
          msgtype: 'm.image',
          body: 'secret.jpg',
          extra: const <String, Object?>{
            'file': <String, Object?>{
              'url': 'mxc://example.org/encrypted-image',
              'v': 'v2',
              'iv': 'fixture-iv',
              'key': <String, Object?>{'kty': 'oct', 'k': 'fixture-key'},
              'hashes': <String, Object?>{'sha256': 'fixture-hash'},
            },
            'info': <String, Object?>{
              'thumbnail_file': <String, Object?>{
                'url': 'mxc://example.org/encrypted-thumbnail',
                'v': 'v2',
                'iv': 'fixture-thumbnail-iv',
                'key': <String, Object?>{
                  'kty': 'oct',
                  'k': 'fixture-thumbnail-key',
                },
                'hashes': <String, Object?>{'sha256': 'fixture-thumbnail-hash'},
              },
            },
          },
        ),
        currentUserId: '@me:example.org',
      );
      expect(encrypted, isNotNull);
      expect(
        encrypted!.attachment!.contentUri,
        'mxc://example.org/encrypted-image',
      );
      expect(
        encrypted.attachment!.encryptedFile?['url'],
        'mxc://example.org/encrypted-image',
      );
      expect(
        encrypted.attachment!.thumbnailContentUri,
        'mxc://example.org/encrypted-thumbnail',
      );
      expect(
        encrypted.attachment!.encryptedThumbnailFile?['url'],
        'mxc://example.org/encrypted-thumbnail',
      );
    },
  );

  test('Matrix timeline projection preserves custom HTML formatted bodies', () {
    final message = TimelineMessage.fromMatrixEvent(
      _event(
        eventId: r'$formatted',
        streamPosition: 1,
        senderId: '@alice:example.org',
        msgtype: 'm.text',
        body: 'Hello rich',
        extra: const <String, Object?>{
          'format': 'org.matrix.custom.html',
          'formatted_body': '<p>Hello <strong>rich</strong></p>',
        },
      ),
      currentUserId: '@me:example.org',
    );

    expect(message, isNotNull);
    expect(message!.body, 'Hello rich');
    expect(message.formattedBody, '<p>Hello <strong>rich</strong></p>');
    expect(message.sentAt, DateTime.utc(2026, 9, 16, 10, 1).toLocal());
  });

  test('Matrix room projection uses replacement content for edit previews', () {
    final cache = MatrixPresentationCache();
    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!alpha:example.org',
            summary: MatrixRoomSummary(
              roomId: '!alpha:example.org',
              displayName: 'Alpha',
              lastActivity: DateTime.utc(2026, 9, 16, 10, 31),
              streamPosition: 2,
              lastEventId: r'$edit',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(
                eventId: r'$original',
                streamPosition: 1,
                senderId: '@alice:example.org',
                senderDisplayName: 'Alice',
                msgtype: 'm.text',
                body: 'Original message',
              ),
              _event(
                eventId: r'$edit',
                streamPosition: 2,
                senderId: '@alice:example.org',
                senderDisplayName: 'Alice',
                msgtype: 'm.text',
                body: '* Edited message',
                extra: const <String, Object?>{
                  'm.new_content': <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'Edited message',
                  },
                  'm.relates_to': <String, Object?>{
                    'rel_type': 'm.replace',
                    'event_id': r'$original',
                  },
                },
              ),
            ],
          ),
        ],
      ),
    );

    final entry = matrixRoomListEntries(cache).single;
    expect(entry.latestSender, 'Alice');
    expect(entry.latestEventBody, 'Edited message');
  });

  test(
    'room reconciliation keeps existing leaf signals while order changes',
    () {
      const alpha = RoomListEntry(
        id: '!alpha:example.org',
        name: 'Alpha',
        latestEventBody: 'Old',
      );
      const beta = RoomListEntry(
        id: '!beta:example.org',
        name: 'Beta',
        latestEventBody: 'Beta event',
      );
      final store = RoomListStateStore(const <RoomListEntry>[alpha, beta]);
      final alphaSignal = store.roomSignal(alpha.id);

      store.reconcile(<RoomListEntry>[
        beta,
        alpha.copyWith(latestEventBody: 'New', unreadCount: 4),
      ]);

      expect(store.roomIds, <String>[beta.id, alpha.id]);
      expect(store.visibleRoomIds.value, <String>[beta.id, alpha.id]);
      expect(store.roomSignal(alpha.id), same(alphaSignal));
      expect(alphaSignal.value.latestEventBody, 'New');
      expect(alphaSignal.value.unreadCount, 4);
    },
  );

  test(
    'Matrix message projection covers text, audio, voice and MIDI events',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final events = <MatrixTimelineEvent>[
        _event(
          eventId: r'$text',
          streamPosition: 1,
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          msgtype: 'm.text',
          body: 'Hello from sync',
        ),
        _event(
          eventId: r'$audio',
          streamPosition: 2,
          senderId: '@alice:example.org',
          msgtype: 'm.audio',
          body: 'song.m4a',
          info: const <String, Object?>{
            'size': 2200000,
            'duration': 65000,
            'mimetype': 'audio/mp4',
          },
        ),
        _event(
          eventId: r'$voice',
          streamPosition: 3,
          senderId: '@me:example.org',
          msgtype: 'm.audio',
          body: 'voice.ogg',
          info: const <String, Object?>{
            'size': 268000,
            'duration': 12000,
            'mimetype': 'audio/ogg',
          },
          extra: const <String, Object?>{
            'org.matrix.msc3245.voice': <String, Object?>{},
          },
        ),
        _event(
          eventId: r'$midi',
          streamPosition: 4,
          senderId: '@alice:example.org',
          msgtype: 'm.file',
          body: 'theme.mid',
          info: const <String, Object?>{'size': 4096, 'mimetype': 'audio/midi'},
        ),
      ];

      controller.applyMatrixEvents(
        '!alpha:example.org',
        events,
        currentUserId: '@me:example.org',
      );
      final messages = controller.messagesFor('!alpha:example.org').value;

      expect(messages, hasLength(4));
      expect(messages[0].sender, 'Alice');
      expect(messages[0].body, 'Hello from sync');
      expect(messages[1].attachment?.kind, TimelineAttachmentKind.audio);
      expect(messages[1].attachment?.durationLabel, '1:05');
      expect(messages[2].attachment?.kind, TimelineAttachmentKind.voice);
      expect(messages[2].mine, isTrue);
      expect(messages[3].attachment?.kind, TimelineAttachmentKind.audio);
      expect(messages[3].attachment?.name, 'theme.mid');
    },
  );

  test('Matrix redactions project as durable deleted-message state', () {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      fixtureProvider: (_) => const [],
    );
    controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
      _event(
        eventId: r'$target',
        streamPosition: 1,
        senderId: '@me:example.org',
        msgtype: 'm.text',
        body: 'Delete me',
      ),
      MatrixTimelineEvent(
        eventId: r'$redaction',
        roomId: '!alpha:example.org',
        senderId: '@me:example.org',
        type: 'm.room.redaction',
        originServerTimestamp: DateTime.utc(2026, 9, 16, 10, 2),
        streamPosition: 2,
        redactsEventId: r'$target',
      ),
    ], currentUserId: '@me:example.org');

    final message = controller.messagesFor('!alpha:example.org').value.single;
    expect(message.id, r'$target');
    expect(message.body, isEmpty);
    expect(message.redacted, isTrue);
  });

  test(
    'Matrix replies project target metadata without changing message order',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
        fixtureProvider: (_) => const [],
      );
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        _event(
          eventId: r'$original',
          streamPosition: 1,
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          msgtype: 'm.text',
          body: 'Original message',
        ),
        _event(
          eventId: r'$reply',
          streamPosition: 2,
          senderId: '@bob:example.org',
          senderDisplayName: 'Bob',
          msgtype: 'm.text',
          body: 'Reply body',
          extra: const <String, Object?>{
            'm.relates_to': <String, Object?>{
              'm.in_reply_to': <String, Object?>{'event_id': r'$original'},
            },
          },
        ),
      ], currentUserId: '@me:example.org');

      final messages = controller.messagesFor('!alpha:example.org').value;
      expect(messages.map((message) => message.id), <String>[
        r'$original',
        r'$reply',
      ]);
      expect(messages[1].replyToMessageId, r'$original');
      expect(messages[1].replyToSender, 'Alice');
      expect(messages[1].replyToBody, 'Original message');
    },
  );

  test('reply sends preserve Matrix target event ID', () async {
    final sendPort = _RecordingSendPort();
    final controller = TimelineController(
      sendPort: sendPort,
      fixtureProvider: (_) => const [],
    );
    controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
      _event(
        eventId: r'$original',
        streamPosition: 1,
        senderId: '@alice:example.org',
        senderDisplayName: 'Alice',
        msgtype: 'm.text',
        body: 'Original message',
      ),
    ], currentUserId: '@me:example.org');
    final original = controller.messagesFor('!alpha:example.org').value.single;

    final local = controller.sendText(
      '!alpha:example.org',
      'Reply body',
      replyTo: original,
    );
    await Future<void>.delayed(Duration.zero);

    expect(local.replyToMessageId, r'$original');
    expect(sendPort.calls, hasLength(1));
    expect(sendPort.calls.single.replyToEventId, r'$original');
    expect(sendPort.calls.single.body, 'Reply body');
  });

  test(
    'Matrix replacements update the original message without adding a row',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
        fixtureProvider: (_) => const [],
      );
      final events = <MatrixTimelineEvent>[
        _event(
          eventId: r'$original',
          streamPosition: 1,
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          msgtype: 'm.text',
          body: 'Original message',
        ),
        _event(
          eventId: r'$edit',
          streamPosition: 2,
          senderId: '@alice:example.org',
          senderDisplayName: 'Alice',
          msgtype: 'm.text',
          body: '* Edited message',
          extra: const <String, Object?>{
            'm.new_content': <String, Object?>{
              'msgtype': 'm.text',
              'body': 'Edited message',
              'format': 'org.matrix.custom.html',
              'formatted_body': '<p>Edited <strong>message</strong></p>',
            },
            'm.relates_to': <String, Object?>{
              'rel_type': 'm.replace',
              'event_id': r'$original',
            },
          },
        ),
      ];

      controller.applyMatrixEvents(
        '!alpha:example.org',
        events,
        currentUserId: '@me:example.org',
      );
      final first = controller.messagesFor('!alpha:example.org').value.single;
      expect(first.id, r'$original');
      expect(first.body, 'Edited message');
      expect(first.formattedBody, '<p>Edited <strong>message</strong></p>');
      expect(first.edited, isTrue);
      expect(first.editHistory, <String>['Original message']);

      controller.applyMatrixEvents(
        '!alpha:example.org',
        events,
        currentUserId: '@me:example.org',
      );
      final replayed = controller
          .messagesFor('!alpha:example.org')
          .value
          .single;
      expect(replayed, same(first));
      expect(replayed.body, 'Edited message');
      expect(replayed.editHistory, <String>['Original message']);
    },
  );

  test('Matrix replacements from a different sender are ignored', () {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      fixtureProvider: (_) => const [],
    );
    controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
      _event(
        eventId: r'$original',
        streamPosition: 1,
        senderId: '@alice:example.org',
        msgtype: 'm.text',
        body: 'Original message',
      ),
      _event(
        eventId: r'$malicious-edit',
        streamPosition: 2,
        senderId: '@mallory:example.org',
        msgtype: 'm.text',
        body: '* Forged edit',
        extra: const <String, Object?>{
          'm.new_content': <String, Object?>{
            'msgtype': 'm.text',
            'body': 'Forged edit',
          },
          'm.relates_to': <String, Object?>{
            'rel_type': 'm.replace',
            'event_id': r'$original',
          },
        },
      ),
    ], currentUserId: '@me:example.org');

    final message = controller.messagesFor('!alpha:example.org').value.single;
    expect(message.body, 'Original message');
    expect(message.edited, isFalse);
    expect(message.editHistory, isEmpty);
  });

  test(
    'edit sends preserve Matrix replacement target and roll back failures',
    () async {
      final editPort = _RecordingEditPort();
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
        editPort: editPort,
        fixtureProvider: (_) => const [],
      );
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        _event(
          eventId: r'$original',
          streamPosition: 1,
          senderId: '@me:example.org',
          msgtype: 'm.text',
          body: 'Original message',
        ),
      ], currentUserId: '@me:example.org');
      final message = controller.messagesFor('!alpha:example.org').value.single;

      controller.editText('!alpha:example.org', message, 'Edited message');
      await Future<void>.delayed(Duration.zero);
      expect(editPort.calls, hasLength(1));
      expect(editPort.calls.single.eventId, r'$original');
      expect(editPort.calls.single.body, 'Edited message');
      expect(message.body, 'Edited message');
      expect(message.edited, isTrue);

      editPort.outcome = TimelineSendOutcome.failed;
      controller.editText('!alpha:example.org', message, 'Rejected edit');
      await Future<void>.delayed(Duration.zero);
      expect(message.body, 'Edited message');
      expect(message.edited, isTrue);
      expect(message.editHistory, <String>['Original message']);
    },
  );

  test(
    'optimistic Matrix edits survive stale sync until replacement arrives',
    () async {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
        editPort: _RecordingEditPort(),
        fixtureProvider: (_) => const [],
      );
      final original = _event(
        eventId: r'$original',
        streamPosition: 1,
        senderId: '@me:example.org',
        msgtype: 'm.text',
        body: 'Original message',
      );
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        original,
      ], currentUserId: '@me:example.org');
      final message = controller.messagesFor('!alpha:example.org').value.single;

      controller.editText('!alpha:example.org', message, 'Edited message');
      await Future<void>.delayed(Duration.zero);
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        original,
      ], currentUserId: '@me:example.org');

      expect(message.body, 'Edited message');
      expect(message.editHistory, <String>['Original message']);

      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        original,
        _event(
          eventId: r'$edit',
          streamPosition: 2,
          senderId: '@me:example.org',
          msgtype: 'm.text',
          body: '* Edited message',
          extra: const <String, Object?>{
            'm.new_content': <String, Object?>{
              'msgtype': 'm.text',
              'body': 'Edited message',
            },
            'm.relates_to': <String, Object?>{
              'rel_type': 'm.replace',
              'event_id': r'$original',
            },
          },
        ),
      ], currentUserId: '@me:example.org');

      expect(
        controller.messagesFor('!alpha:example.org').value.single,
        same(message),
      );
      expect(message.body, 'Edited message');
      expect(message.editHistory, <String>['Original message']);
    },
  );

  test('Matrix transaction IDs stay unique across controller restarts', () {
    final firstController = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      fixtureProvider: (_) => const [],
    );
    final secondController = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      fixtureProvider: (_) => const [],
    );

    final first = firstController.sendText('!alpha:example.org', 'First');
    final second = secondController.sendText('!alpha:example.org', 'Second');

    expect(first.id, 'kite-local-0');
    expect(second.id, 'kite-local-0');
    expect(first.transactionId, startsWith('kite-txn-'));
    expect(second.transactionId, startsWith('kite-txn-'));
    expect(first.transactionId, isNot(second.transactionId));
  });

  test('Matrix transaction IDs reconcile optimistic local sends', () async {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
    controller.applyMatrixEvents(
      '!alpha:example.org',
      const <MatrixTimelineEvent>[],
      currentUserId: '@me:example.org',
    );
    final local = controller.sendText('!alpha:example.org', 'Sent for real');
    await Future<void>.delayed(Duration.zero);

    controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
      _event(
        eventId: r'$real',
        streamPosition: 9,
        senderId: '@me:example.org',
        msgtype: 'm.text',
        body: 'Sent for real',
        transactionId: local.transactionId,
      ),
    ], currentUserId: '@me:example.org');

    final messages = controller.messagesFor('!alpha:example.org').value;
    expect(messages, hasLength(1));
    expect(messages.single.id, r'$real');
    expect(messages.single.sendState.value, TimelineSendState.sent);
  });

  test(
    'incremental Matrix projection preserves old identity and local sends',
    () {
      final controller = TimelineController(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final first = _event(
        eventId: r'$first',
        streamPosition: 1,
        senderId: '@alice:example.org',
        msgtype: 'm.text',
        body: 'First',
      );
      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        first,
      ], currentUserId: '@me:example.org');
      final firstMessage = controller
          .messagesFor('!alpha:example.org')
          .value
          .single;
      final local = controller.sendText('!alpha:example.org', 'Queued locally');
      final second = _event(
        eventId: r'$second',
        streamPosition: 2,
        senderId: '@bob:example.org',
        msgtype: 'm.text',
        body: 'Second',
      );

      controller.applyMatrixEvents('!alpha:example.org', <MatrixTimelineEvent>[
        first,
        second,
      ], currentUserId: '@me:example.org');
      final messages = controller.messagesFor('!alpha:example.org').value;

      expect(messages, hasLength(3));
      expect(messages[0], same(firstMessage));
      expect(messages[1].id, r'$second');
      expect(messages[2], same(local));
    },
  );
}

final class _RecordingEditPort implements TimelineEditPort {
  TimelineSendOutcome outcome = TimelineSendOutcome.sent;
  final List<
    ({String roomId, String transactionId, String eventId, String body})
  >
  calls =
      <({String roomId, String transactionId, String eventId, String body})>[];

  @override
  Future<TimelineSendOutcome> editText({
    required String roomId,
    required String transactionId,
    required String eventId,
    required String body,
  }) async {
    calls.add((
      roomId: roomId,
      transactionId: transactionId,
      eventId: eventId,
      body: body,
    ));
    return outcome;
  }
}

final class _RecordingSendPort implements TimelineSendPort {
  final List<
    ({String roomId, String transactionId, String body, String? replyToEventId})
  >
  calls =
      <
        ({
          String roomId,
          String transactionId,
          String body,
          String? replyToEventId,
        })
      >[];

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
  }) async {
    calls.add((
      roomId: roomId,
      transactionId: transactionId,
      body: body,
      replyToEventId: replyToEventId,
    ));
    return TimelineSendOutcome.sent;
  }
}

MatrixTimelineEvent _event({
  required String eventId,
  required int streamPosition,
  required String senderId,
  String? senderDisplayName,
  String? senderAvatarUrl,
  required String msgtype,
  required String body,
  Map<String, Object?>? info,
  String? transactionId,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: '!alpha:example.org',
    senderId: senderId,
    senderDisplayName: senderDisplayName,
    senderAvatarUrl: senderAvatarUrl,
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 16, 10, streamPosition),
    streamPosition: streamPosition,
    transactionId: transactionId,
    content: <String, Object?>{
      'msgtype': msgtype,
      'body': body,
      'info': ?info,
      ...extra,
    },
  );
}
