import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/features/timeline/timeline_share.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

void main() {
  test('Matrix home binding preserves the injected link opener', () async {
    final cache = MatrixPresentationCache();
    final opened = <Uri>[];
    final linkOpenPort = PlatformTimelineLinkOpenPort(
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
      linkOpenPort: linkOpenPort,
    );
    addTearDown(binding.dispose);

    final uri = Uri.parse('https://element.io/help');
    await binding.controller.openLink(uri);

    expect(opened, <Uri>[uri]);
  });

  test('Matrix home binding preserves the injected share port', () async {
    final cache = MatrixPresentationCache();
    final shared = <String>[];
    final sharePort = PlatformTimelineSharePort(
      launcher: (text) async {
        shared.add(text);
      },
    );
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
      sharePort: sharePort,
    );
    addTearDown(binding.dispose);

    await binding.controller.shareMessage(
      '!room:example.org',
      TimelineMessage(
        id: r'$event:example.org',
        sender: 'Me',
        body: 'Production share',
        mine: true,
        timeLabel: '03:12',
      ),
    );

    expect(shared.single, contains('Production share'));
    expect(shared.single, contains('%24event%3Aexample.org'));
  });

  test('Matrix home binding preserves the injected moderation port', () async {
    final cache = MatrixPresentationCache();
    final reports = <({String roomId, String eventId, String reason})>[];
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
      moderationPort: MatrixTimelineModerationPort(({
        required roomId,
        required eventId,
        required reason,
      }) async {
        reports.add((roomId: roomId, eventId: eventId, reason: reason));
      }),
    );
    addTearDown(binding.dispose);

    await binding.controller.reportMessage(
      '!room:example.org',
      TimelineMessage(
        id: r'$event:example.org',
        sender: 'Spammer',
        body: 'Spam',
        mine: false,
        timeLabel: '03:13',
      ),
      '  abuse  ',
    );

    expect(reports, <({String roomId, String eventId, String reason})>[
      (
        roomId: '!room:example.org',
        eventId: r'$event:example.org',
        reason: 'abuse',
      ),
    ]);
  });

  test('Matrix timeline send port preserves reply targets', () async {
    final plainBodies = <String>[];
    final replies = <({String body, String eventId})>[];
    final port = MatrixTimelineSendPort(
      ({required roomId, required transactionId, required body}) async {
        plainBodies.add(body);
      },
      sendReply:
          ({
            required roomId,
            required transactionId,
            required body,
            required replyToEventId,
          }) async {
            replies.add((body: body, eventId: replyToEventId));
          },
    );

    expect(
      await port.sendText(
        roomId: '!room:example.org',
        transactionId: 'txn-1',
        body: 'Plain',
      ),
      TimelineSendOutcome.sent,
    );
    expect(
      await port.sendText(
        roomId: '!room:example.org',
        transactionId: 'txn-2',
        body: 'Reply',
        replyToEventId: r'$original',
      ),
      TimelineSendOutcome.sent,
    );

    expect(plainBodies, <String>['Plain']);
    expect(replies, <({String body, String eventId})>[
      (body: 'Reply', eventId: r'$original'),
    ]);
  });

  test('Matrix timeline edit port preserves replacement targets', () async {
    final edits =
        <
          ({String roomId, String transactionId, String eventId, String body})
        >[];
    final port = MatrixTimelineEditPort(({
      required roomId,
      required transactionId,
      required eventId,
      required body,
    }) async {
      edits.add((
        roomId: roomId,
        transactionId: transactionId,
        eventId: eventId,
        body: body,
      ));
    });

    expect(
      await port.editText(
        roomId: '!room:example.org',
        transactionId: 'txn-edit-1',
        eventId: r'$original',
        body: 'Edited',
      ),
      TimelineSendOutcome.sent,
    );
    expect(
      edits,
      <({String roomId, String transactionId, String eventId, String body})>[
        (
          roomId: '!room:example.org',
          transactionId: 'txn-edit-1',
          eventId: r'$original',
          body: 'Edited',
        ),
      ],
    );
  });

  testWidgets('empty Matrix home shows loading until the first sync batch', (
    tester,
  ) async {
    final cache = MatrixPresentationCache();

    await tester.pumpWidget(
      KiteApp(
        home: MatrixHomeScreen(
          cache: cache,
          currentUserId: '@me:example.org',
          sendPort: MatrixTimelineSendPort(
            ({required roomId, required transactionId, required body}) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('room-list-loading')), findsOneWidget);
    expect(find.text('No chats found'), findsNothing);

    cache.applySync(
      const MatrixSyncBatch(cursor: 'sync-1', rooms: <MatrixRoomDelta>[]),
    );
    await tester.pump();

    expect(find.byKey(const Key('room-list-loading')), findsNothing);
    expect(find.text('No chats found'), findsOneWidget);
  });

  test('cached Matrix state replaces fixture room and timeline defaults', () {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!real:example.org',
            displayName: 'Real room',
            lastActivity: DateTime.utc(2026, 9, 16, 11),
            streamPosition: 1,
            lastEventId: r'$cached',
            unreadCount: 2,
            highlightCount: 1,
            hasActiveCall: true,
            isFavourite: true,
            isMuted: true,
            isDirect: true,
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!real:example.org': <MatrixTimelineEvent>[
            _event(
              eventId: r'$cached',
              body: 'Cached before sync',
              streamPosition: 1,
            ),
          ],
        },
      ),
    );
    final selectedRoom = signal('kite');
    final controller = TimelineController();
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: selectedRoom,
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    expect(binding.roomListStore.roomIds, <String>['!real:example.org']);
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.name,
      'Real room',
    );
    expect(selectedRoom.value, '!real:example.org');
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.hasMention,
      isTrue,
    );
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.hasActiveCall,
      isTrue,
    );
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.isFavourite,
      isTrue,
    );
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.isMuted,
      isTrue,
    );
    expect(
      binding.roomListStore.roomSignal('!real:example.org').value.isDirect,
      isTrue,
    );
    expect(
      binding.roomListStore
          .roomSignal('!real:example.org')
          .value
          .hasMutedActivity,
      isTrue,
    );
    expect(
      controller.messagesFor('!real:example.org').value.single.body,
      'Cached before sync',
    );
    expect(controller.messagesFor('kite').value, isEmpty);
  });

  test('cached Matrix edits project without a signal cycle', () {
    const roomId = '!edited:example.org';
    const originalEventId = r'$original';
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: roomId,
            displayName: 'Edited room',
            lastActivity: DateTime.utc(2026, 9, 16, 11, 2),
            streamPosition: 2,
            lastEventId: r'$replacement',
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          roomId: <MatrixTimelineEvent>[
            MatrixTimelineEvent(
              eventId: originalEventId,
              roomId: roomId,
              senderId: '@alice:example.org',
              type: 'm.room.message',
              originServerTimestamp: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              content: const <String, Object?>{
                'msgtype': 'm.text',
                'body': 'Before edit',
              },
            ),
            MatrixTimelineEvent(
              eventId: r'$replacement',
              roomId: roomId,
              senderId: '@alice:example.org',
              type: 'm.room.message',
              originServerTimestamp: DateTime.utc(2026, 9, 16, 11, 2),
              streamPosition: 2,
              content: const <String, Object?>{
                'msgtype': 'm.text',
                'body': '* After edit',
                'm.new_content': <String, Object?>{
                  'msgtype': 'm.text',
                  'body': 'After edit',
                },
                'm.relates_to': <String, Object?>{
                  'rel_type': 'm.replace',
                  'event_id': originalEventId,
                },
              },
            ),
          ],
        },
      ),
    );
    final controller = TimelineController();

    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: signal(roomId),
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    final message = controller.messagesFor(roomId).value.single;
    expect(message.body, 'After edit');
    expect(message.edited, isTrue);
    expect(message.editHistoryState.value, <String>['Before edit']);
  });

  test('cached invites project through the production invite port', () async {
    final calls = <(String, bool)>[];
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: const <MatrixRoomSummary>[],
        invites: const <MatrixRoomInvite>[
          MatrixRoomInvite(
            roomId: '!invite:example.org',
            roomName: 'Invite room',
            inviterId: '@alice:example.org',
            inviterDisplayName: 'Alice',
            memberCount: 5,
            description: 'Production invite',
          ),
        ],
      ),
    );
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
      invitePort: MatrixRoomInvitePort((roomId, accept) async {
        calls.add((roomId, accept));
      }),
    );
    addTearDown(binding.dispose);

    expect(binding.inviteStore.visibleInviteIds.value, <String>[
      '!invite:example.org',
    ]);
    expect(
      binding.inviteStore.invite('!invite:example.org').inviterName,
      'Alice',
    );

    await binding.inviteStore.accept('!invite:example.org');
    expect(calls, <(String, bool)>[('!invite:example.org', true)]);
    expect(binding.inviteStore.visibleInviteIds.value, isEmpty);

    cache.applySync(
      const MatrixSyncBatch(
        cursor: 'unrelated-sync',
        rooms: <MatrixRoomDelta>[],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(binding.inviteStore.visibleInviteIds.value, isEmpty);

    cache.applySync(
      const MatrixSyncBatch(
        cursor: 'after-accept',
        rooms: <MatrixRoomDelta>[],
        removedInviteRoomIds: <String>['!invite:example.org'],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cache.invites.value, isEmpty);
  });

  test('incremental cache updates reconcile rooms and timelines', () async {
    final cache = MatrixPresentationCache();
    final controller = TimelineController();
    final selectedRoom = signal('missing');
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: selectedRoom,
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    cache.applySync(
      MatrixSyncBatch(
        cursor: 's1',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!real:example.org',
            summary: MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Synced room',
              lastActivity: DateTime.utc(2026, 9, 16, 11, 10),
              streamPosition: 1,
              lastEventId: r'$one',
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(eventId: r'$one', body: 'One', streamPosition: 1),
            ],
            typingUsers: const <String>['Alice'],
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(binding.roomListStore.roomIds, <String>['!real:example.org']);
    expect(selectedRoom.value, '!real:example.org');
    expect(
      controller.messagesFor('!real:example.org').value.single.body,
      'One',
    );
    expect(controller.typingUsersFor('!real:example.org').value, <String>[
      'Alice',
    ]);

    cache.applySync(
      MatrixSyncBatch(
        cursor: 's2',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!real:example.org',
            summary: MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Synced room renamed',
              lastActivity: DateTime.utc(2026, 9, 16, 11, 11),
              streamPosition: 2,
              lastEventId: r'$two',
              unreadCount: 3,
            ),
            timelineEvents: <MatrixTimelineEvent>[
              _event(eventId: r'$two', body: 'Two', streamPosition: 2),
            ],
            typingUsers: const <String>[],
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final room = binding.roomListStore.roomSignal('!real:example.org').value;
    expect(room.name, 'Synced room renamed');
    expect(room.latestEventBody, 'Two');
    expect(room.unreadCount, 3);
    expect(
      controller
          .messagesFor('!real:example.org')
          .value
          .map((message) => message.body),
      <String>['One', 'Two'],
    );
    expect(controller.typingUsersFor('!real:example.org').value, isEmpty);
  });

  test(
    'Matrix read receipts project into existing timeline receipt UI state',
    () async {
      final cache = MatrixPresentationCache();
      final controller = TimelineController(fixtureProvider: (_) => const []);
      final selectedRoom = signal('missing');
      final binding = MatrixHomePresentationBinding(
        cache: cache,
        currentUserId: '@me:example.org',
        controller: controller,
        selectedRoom: selectedRoom,
        sendPort: MatrixTimelineSendPort(
          ({required roomId, required transactionId, required body}) async {},
        ),
      );
      addTearDown(binding.dispose);

      cache.applySync(
        MatrixSyncBatch(
          cursor: 'receipt-sync',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!real:example.org',
              summary: MatrixRoomSummary(
                roomId: '!real:example.org',
                displayName: 'Receipt room',
                lastActivity: DateTime.utc(2026, 9, 25, 3, 40),
                streamPosition: 2,
                lastEventId: r'$incoming',
              ),
              timelineEvents: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$mine',
                  roomId: '!real:example.org',
                  senderId: '@me:example.org',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 25, 3, 40),
                  streamPosition: 1,
                  content: const <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'Mine',
                  },
                ),
                MatrixTimelineEvent(
                  eventId: r'$incoming',
                  roomId: '!real:example.org',
                  senderId: '@alice:example.org',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 25, 3, 41),
                  streamPosition: 2,
                  content: const <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'After yours',
                  },
                ),
              ],
              readReceipts: const <MatrixReadReceipt>[
                MatrixReadReceipt(
                  eventId: r'$incoming',
                  userId: '@alice:example.org',
                  displayName: 'Alice',
                ),
              ],
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(selectedRoom.value, '!real:example.org');
      expect(
        controller.messagesFor('!real:example.org').value.first.readBy,
        <String>['Alice'],
      );
    },
  );

  test(
    'Matrix fully-read state projects the first unread timeline marker',
    () async {
      final cache = MatrixPresentationCache();
      final controller = TimelineController(fixtureProvider: (_) => const []);
      final selectedRoom = signal('missing');
      final binding = MatrixHomePresentationBinding(
        cache: cache,
        currentUserId: '@me:example.org',
        controller: controller,
        selectedRoom: selectedRoom,
        sendPort: MatrixTimelineSendPort(
          ({required roomId, required transactionId, required body}) async {},
        ),
      );
      addTearDown(binding.dispose);

      cache.applySync(
        MatrixSyncBatch(
          cursor: 'read-marker-sync',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!real:example.org',
              summary: MatrixRoomSummary(
                roomId: '!real:example.org',
                displayName: 'Unread room',
                lastActivity: DateTime.utc(2026, 9, 25, 4, 10),
                streamPosition: 4,
                lastEventId: r'$three',
                fullyReadEventId: r'$hidden-state',
                unreadMessageCount: 2,
              ),
              timelineEvents: <MatrixTimelineEvent>[
                _event(eventId: r'$one', body: 'One', streamPosition: 1),
                MatrixTimelineEvent(
                  eventId: r'$hidden-state',
                  roomId: '!real:example.org',
                  senderId: '@alice:example.org',
                  type: 'm.room.topic',
                  originServerTimestamp: DateTime.utc(2026, 9, 25, 4, 8),
                  streamPosition: 2,
                  content: const <String, Object?>{
                    'topic': 'Hidden marker target',
                  },
                ),
                _event(eventId: r'$two', body: 'Two', streamPosition: 3),
                _event(eventId: r'$three', body: 'Three', streamPosition: 4),
              ],
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(selectedRoom.value, '!real:example.org');
      expect(controller.unreadMarkerFor('!real:example.org').value, r'$two');
    },
  );

  test('recent Matrix timelines are projected eagerly', () async {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!alpha:example.org',
            displayName: 'Alpha',
            lastActivity: DateTime.utc(2026, 9, 16, 11, 10),
            streamPosition: 2,
            lastEventId: r'$alpha',
          ),
          MatrixRoomSummary(
            roomId: '!beta:example.org',
            displayName: 'Beta',
            lastActivity: DateTime.utc(2026, 9, 16, 11),
            streamPosition: 1,
            lastEventId: r'$beta',
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!alpha:example.org': <MatrixTimelineEvent>[
            _event(
              eventId: r'$alpha',
              body: 'Alpha message',
              streamPosition: 2,
              roomId: '!alpha:example.org',
            ),
          ],
          '!beta:example.org': <MatrixTimelineEvent>[
            _event(
              eventId: r'$beta',
              body: 'Beta message',
              streamPosition: 1,
              roomId: '!beta:example.org',
            ),
          ],
        },
      ),
    );
    final controller = TimelineController();
    final selectedRoom = signal('!alpha:example.org');
    final binding = MatrixHomePresentationBinding(
      cache: cache,
      currentUserId: '@me:example.org',
      controller: controller,
      selectedRoom: selectedRoom,
      sendPort: MatrixTimelineSendPort(
        ({required roomId, required transactionId, required body}) async {},
      ),
    );
    addTearDown(binding.dispose);

    expect(
      controller.messagesFor('!alpha:example.org').value.single.body,
      'Alpha message',
    );
    expect(
      controller.messagesFor('!beta:example.org').value.single.body,
      'Beta message',
    );

    selectedRoom.value = '!beta:example.org';
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.messagesFor('!beta:example.org').value.single.body,
      'Beta message',
    );
  });

  testWidgets(
    'Matrix home composer sends through its production timeline port',
    (tester) async {
      final calls = <String>[];
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Real room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              lastEventId: r'$cached',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!real:example.org': <MatrixTimelineEvent>[
              _event(
                eventId: r'$cached',
                body: 'Cached before send',
                streamPosition: 1,
              ),
            ],
          },
        ),
      );

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              calls.add('$roomId|$transactionId|$body');
            }),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Real room'), findsWidgets);
      expect(find.text('Cached before send'), findsOneWidget);
      expect(find.text('Design Lab'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'From production composer',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(
        calls.single,
        allOf(
          startsWith('!real:example.org|kite-txn-'),
          endsWith('|From production composer'),
        ),
      );
      expect(find.text('From production composer'), findsOneWidget);

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(
              ({
                required roomId,
                required transactionId,
                required body,
              }) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('From production composer'), findsOneWidget);
      expect(find.text('Cached before send'), findsOneWidget);
    },
  );

  testWidgets(
    'Matrix room details loads real member data without local moderation fallbacks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!real:matrix.test',
              displayName: 'Real room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              lastEventId: r'$cached',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!real:matrix.test': <MatrixTimelineEvent>[
              _event(
                eventId: r'$cached',
                body: 'Cached message',
                streamPosition: 1,
                roomId: '!real:matrix.test',
              ),
            ],
          },
        ),
      );
      final loadedRooms = <String>[];

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:matrix.test',
            sendPort: MatrixTimelineSendPort(
              ({
                required roomId,
                required transactionId,
                required body,
              }) async {},
            ),
            roomMembersLoader: (roomId) async {
              loadedRooms.add(roomId);
              return RoomMembersStore(
                roomId: roomId,
                currentUserId: '@me:matrix.test',
                members: const <RoomMember>[
                  RoomMember(
                    userId: '@me:matrix.test',
                    displayName: 'Me',
                    membership: RoomMembership.joined,
                    powerLevel: 100,
                  ),
                  RoomMember(
                    userId: '@alice:matrix.test',
                    displayName: 'Alice Real',
                    membership: RoomMembership.joined,
                    powerLevel: 50,
                  ),
                ],
                powerLevels: const MatrixPowerLevels(
                  users: <String, int>{
                    '@me:matrix.test': 100,
                    '@alice:matrix.test': 50,
                  },
                ),
              );
            },
            memberModerationEnabled: false,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('room-details-button')));
      await tester.pumpAndSettle();

      expect(loadedRooms, <String>['!real:matrix.test']);
      expect(
        find.byKey(const Key('member-@alice:matrix.test')),
        findsOneWidget,
      );
      expect(find.text('Alice Real'), findsOneWidget);
      expect(find.textContaining('example.org'), findsNothing);

      await tester.tap(find.byKey(const Key('member-@alice:matrix.test')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('member-profile-sheet')), findsOneWidget);
      expect(find.byKey(const Key('member-promote')), findsNothing);
      expect(find.byKey(const Key('member-demote')), findsNothing);
      expect(find.byKey(const Key('member-kick')), findsNothing);
      expect(find.byKey(const Key('member-ban')), findsNothing);
    },
  );

  testWidgets(
    'compact Matrix timeline keeps the production send port after navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final calls = <String>[];
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!mobile:example.org',
              displayName: 'Mobile room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 1,
              lastEventId: r'$mobile',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!mobile:example.org': <MatrixTimelineEvent>[
              MatrixTimelineEvent(
                eventId: r'$mobile',
                roomId: '!mobile:example.org',
                senderId: '@alice:example.org',
                type: 'm.room.message',
                originServerTimestamp: DateTime.utc(2026, 9, 16, 11),
                streamPosition: 1,
                content: const <String, Object?>{
                  'msgtype': 'm.text',
                  'body': 'Cached mobile message',
                },
              ),
            ],
          },
        ),
      );

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              calls.add('$roomId|$transactionId|$body');
            }),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('room-!mobile:example.org')));
      await tester.pumpAndSettle();
      expect(find.text('Cached mobile message'), findsOneWidget);
      expect(find.byKey(const Key('composer-attach')), findsOneWidget);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      expect(find.byKey(const Key('composer-send')), findsOneWidget);
      expect(find.byKey(const Key('composer-format-toggle')), findsNothing);
      expect(find.byKey(const Key('composer-emoji')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('composer-field')),
        'From compact composer',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(
        calls.single,
        allOf(
          startsWith('!mobile:example.org|kite-txn-'),
          endsWith('|From compact composer'),
        ),
      );
    },
  );

  testWidgets('short Matrix timelines request and render older history', (
    tester,
  ) async {
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!real:example.org',
            displayName: 'Real room',
            lastActivity: DateTime.utc(2026, 9, 16, 11),
            streamPosition: 2,
            lastEventId: r'$newer',
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!real:example.org': <MatrixTimelineEvent>[
            _event(
              eventId: r'$newer',
              body: 'Newer message',
              streamPosition: 2,
            ),
          ],
        },
      ),
    );
    _markSyncReady(cache);
    var historyRequests = 0;

    await tester.pumpWidget(
      KiteApp(
        home: MatrixHomeScreen(
          cache: cache,
          currentUserId: '@me:example.org',
          sendPort: MatrixTimelineSendPort(
            ({required roomId, required transactionId, required body}) async {},
          ),
          onTimelineHistoryRequested: (roomId, oldestVisibleIndex) async {
            historyRequests += 1;
            if (historyRequests != 1) return;
            cache.applyPagination(
              MatrixPaginationPage(
                roomId: roomId,
                events: <MatrixTimelineEvent>[
                  _event(
                    eventId: r'$older',
                    body: 'Older message',
                    streamPosition: 1,
                  ),
                ],
                reachedStart: true,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(historyRequests, greaterThanOrEqualTo(1));
    expect(find.text('Older message'), findsOneWidget);
    expect(find.text('Newer message'), findsOneWidget);
  });

  testWidgets(
    'recent sync completes before back-pagination starts after cache invalidation',
    (tester) async {
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Real room',
              lastActivity: DateTime.utc(2026, 9, 16, 11),
              streamPosition: 2,
              lastEventId: r'$newer',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!real:example.org': <MatrixTimelineEvent>[
              _event(
                eventId: r'$newer',
                body: 'Cached message',
                streamPosition: 2,
              ),
            ],
          },
        ),
      );
      final historyStarted = Completer<void>();
      final releaseHistory = Completer<void>();
      var historyRequests = 0;

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(
              ({
                required roomId,
                required transactionId,
                required body,
              }) async {},
            ),
            onTimelineHistoryRequested: (roomId, oldestVisibleIndex) async {
              historyRequests += 1;
              if (!historyStarted.isCompleted) historyStarted.complete();
              await releaseHistory.future;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(historyRequests, 0);
      expect(find.byKey(const Key('timeline-history-loading')), findsOneWidget);

      _markSyncReady(cache);
      await tester.pump();
      await tester.pump();
      expect(historyStarted.isCompleted, isTrue);
      expect(historyRequests, 1);
      expect(find.byKey(const Key('timeline-history-loading')), findsOneWidget);

      releaseHistory.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timeline-history-loading')), findsNothing);
    },
  );

  testWidgets('long Matrix timelines request history only at the oldest edge', (
    tester,
  ) async {
    final events = List<MatrixTimelineEvent>.generate(
      60,
      (index) => _event(
        eventId: '\$event-$index',
        body: 'Message $index',
        streamPosition: index + 1,
      ),
    );
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!real:example.org',
            displayName: 'Real room',
            lastActivity: DateTime.utc(2026, 9, 16, 11),
            streamPosition: 60,
            lastEventId: r'$event-59',
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!real:example.org': events,
        },
      ),
    );
    _markSyncReady(cache);
    var historyRequests = 0;

    await tester.pumpWidget(
      KiteApp(
        home: MatrixHomeScreen(
          cache: cache,
          currentUserId: '@me:example.org',
          sendPort: MatrixTimelineSendPort(
            ({required roomId, required transactionId, required body}) async {},
          ),
          onTimelineHistoryRequested: (roomId, oldestVisibleIndex) async {
            historyRequests += 1;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(historyRequests, 0);

    final messageList = find.byKey(const Key('message-list'));
    for (var attempt = 0; attempt < 20 && historyRequests == 0; attempt += 1) {
      await tester.drag(messageList, const Offset(0, 500));
      await tester.pump();
    }

    expect(historyRequests, 1);

    await tester.drag(messageList, const Offset(0, -500));
    await tester.pump();
    for (var attempt = 0; attempt < 20 && historyRequests == 1; attempt += 1) {
      await tester.drag(messageList, const Offset(0, 500));
      await tester.pump();
    }

    expect(historyRequests, 2);
  });

  testWidgets(
    'back-pagination preserves the visible timeline anchor at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final events = List<MatrixTimelineEvent>.generate(
        60,
        (index) => _event(
          eventId: '\$event-$index',
          body: 'Message $index',
          streamPosition: index + 31,
        ),
      );
      final cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(
          rooms: <MatrixRoomSummary>[
            MatrixRoomSummary(
              roomId: '!real:example.org',
              displayName: 'Real room',
              lastActivity: DateTime.utc(2026, 9, 16, 12),
              streamPosition: 90,
              lastEventId: r'$event-59',
            ),
          ],
          timelines: <String, List<MatrixTimelineEvent>>{
            '!real:example.org': events,
          },
        ),
      );
      _markSyncReady(cache);
      final historyStarted = Completer<void>();
      final releaseHistory = Completer<void>();
      var historyRequests = 0;

      await tester.pumpWidget(
        KiteApp(
          home: MatrixHomeScreen(
            cache: cache,
            currentUserId: '@me:example.org',
            sendPort: MatrixTimelineSendPort(
              ({
                required roomId,
                required transactionId,
                required body,
              }) async {},
            ),
            onTimelineHistoryRequested: (roomId, oldestVisibleIndex) async {
              historyRequests += 1;
              if (historyRequests != 1) return;
              if (!historyStarted.isCompleted) historyStarted.complete();
              await releaseHistory.future;
              cache.applyPagination(
                MatrixPaginationPage(
                  roomId: roomId,
                  events: List<MatrixTimelineEvent>.generate(
                    30,
                    (index) => _event(
                      eventId: '\$older-$index',
                      body: 'Older message $index',
                      streamPosition: index + 1,
                    ),
                  ),
                  reachedStart: true,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final messageList = find.byKey(const Key('message-list'));
      final anchor = find.byKey(const Key(r'message-bubble-$event-5'));
      await tester.scrollUntilVisible(
        anchor,
        240,
        scrollable: find
            .descendant(of: messageList, matching: find.byType(Scrollable))
            .first,
      );
      for (
        var attempt = 0;
        attempt < 20 && !historyStarted.isCompleted;
        attempt += 1
      ) {
        await tester.drag(messageList, const Offset(0, 300));
        await tester.pump();
      }
      expect(historyStarted.isCompleted, isTrue);
      expect(anchor, findsOneWidget);

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: messageList, matching: find.byType(Scrollable))
            .first,
      );
      final anchorRect = tester.getRect(anchor);
      releaseHistory.complete();

      double? settledPixels;
      for (
        var sample = 0;
        sample < PerformanceContract.motionSamples;
        sample += 1
      ) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(anchor), anchorRect);
        settledPixels ??= scrollable.position.pixels;
        expect(scrollable.position.pixels, settledPixels);
        expect(tester.takeException(), isNull);
      }
      final paginatedEvents = cache.snapshot().timelines['!real:example.org']!;
      expect(paginatedEvents, hasLength(90));
      expect(paginatedEvents.first.eventId, r'$older-0');
      expect(find.text('Older message 0'), findsNothing);
    },
  );

  testWidgets('large timeline keeps rendered message widgets virtualized', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const eventCount = 2000;
    final events = List<MatrixTimelineEvent>.generate(
      eventCount,
      (index) => _event(
        eventId: '\$virtual-$index',
        body: 'Virtualized message $index',
        streamPosition: index,
      ),
      growable: false,
    );
    final cache = MatrixPresentationCache(
      initialSnapshot: MatrixPresentationSnapshot(
        rooms: <MatrixRoomSummary>[
          MatrixRoomSummary(
            roomId: '!real:example.org',
            displayName: 'Real room',
            lastActivity: DateTime.utc(2026, 9, 16, 12),
            streamPosition: eventCount,
            lastEventId: r'$virtual-1999',
          ),
        ],
        timelines: <String, List<MatrixTimelineEvent>>{
          '!real:example.org': events,
        },
      ),
    );

    await tester.pumpWidget(
      KiteApp(
        home: MatrixHomeScreen(
          cache: cache,
          currentUserId: '@me:example.org',
          sendPort: MatrixTimelineSendPort(
            ({required roomId, required transactionId, required body}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      cache.snapshot().timelines['!real:example.org'],
      hasLength(eventCount),
    );
    final messageList = find.byKey(const Key('message-list'));
    Finder mountedMessageBubbles() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('message-bubble-');
    });

    final initiallyMounted = mountedMessageBubbles().evaluate().length;
    expect(initiallyMounted, greaterThan(0));
    expect(initiallyMounted, lessThan(200));
    expect(find.byKey(const Key(r'message-bubble-$virtual-0')), findsNothing);
    expect(
      find.byKey(const Key(r'message-bubble-$virtual-1999')),
      findsOneWidget,
    );

    for (var index = 0; index < 12; index += 1) {
      await tester.drag(messageList, const Offset(0, 500));
      await tester.pump();
    }

    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: messageList, matching: find.byType(Scrollable)).first,
    );
    expect(
      scrollable.position.pixels,
      greaterThan(scrollable.position.minScrollExtent),
    );
    expect(mountedMessageBubbles().evaluate().length, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  test(
    'production send port settles optimistic messages from real sender',
    () async {
      final calls = <String>[];
      var fail = false;
      final port = MatrixTimelineSendPort(({
        required roomId,
        required transactionId,
        required body,
      }) async {
        calls.add('$roomId|$transactionId|$body');
        if (fail) throw StateError('network failure');
      });
      final controller = TimelineController(
        sendPort: port,
        fixtureProvider: (_) => const [],
      );

      final sent = controller.sendText('!room:example.org', 'Sent');
      await Future<void>.delayed(Duration.zero);
      expect(sent.sendState.value, TimelineSendState.sent);
      expect(
        calls.single,
        allOf(startsWith('!room:example.org|kite-txn-'), endsWith('|Sent')),
      );

      fail = true;
      final failed = controller.sendText('!room:example.org', 'Failed');
      await Future<void>.delayed(Duration.zero);
      expect(failed.sendState.value, TimelineSendState.failed);
    },
  );
}

void _markSyncReady(MatrixPresentationCache cache) {
  cache.applySync(
    const MatrixSyncBatch(cursor: 'ready', rooms: <MatrixRoomDelta>[]),
  );
}

MatrixTimelineEvent _event({
  required String eventId,
  required String body,
  required int streamPosition,
  String roomId = '!real:example.org',
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: roomId,
    senderId: '@alice:example.org',
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 16, 11, streamPosition),
    streamPosition: streamPosition,
    content: <String, Object?>{'msgtype': 'm.text', 'body': body},
  );
}
