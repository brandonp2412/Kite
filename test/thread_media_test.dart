import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_media_viewer.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _RecordingThreadMediaActionPort implements ThreadMediaActionPort {
  final List<
    ({String action, String roomId, String parentEventId, String replyId})
  >
  calls =
      <
        ({String action, String roomId, String parentEventId, String replyId})
      >[];

  @override
  Future<void> save({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  }) async {
    calls.add((
      action: 'save',
      roomId: roomId,
      parentEventId: parentEventId,
      replyId: reply.id,
    ));
  }

  @override
  Future<void> share({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  }) async {
    calls.add((
      action: 'share',
      roomId: roomId,
      parentEventId: parentEventId,
      replyId: reply.id,
    ));
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: const DeterministicThreadSubscriptionPort(),
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  test(
    'thread media model only browses media from the current thread',
    () async {
      final actionPort = _RecordingThreadMediaActionPort();
      final parent = TimelineMessage(
        id: 'parent',
        sender: 'Alice',
        body: 'Parent',
        mine: false,
        timeLabel: '10:00',
      );
      final replies = <ThreadReply>[
        ThreadReply(
          id: 'image-reply',
          sender: 'Alice',
          body: 'Image caption',
          mine: false,
          timeLabel: '10:01',
          attachment: const TimelineAttachment(
            id: 'image',
            kind: TimelineAttachmentKind.image,
            name: 'image.jpg',
            sizeLabel: '2 MB · Photo',
          ),
        ),
        ThreadReply(
          id: 'file-reply',
          sender: 'You',
          body: '',
          mine: true,
          timeLabel: '10:02',
          attachment: const TimelineAttachment(
            id: 'file',
            kind: TimelineAttachmentKind.file,
            name: 'notes.pdf',
            sizeLabel: '400 KB · PDF',
          ),
        ),
        ThreadReply(
          id: 'video-reply',
          sender: 'Mina',
          body: 'Video caption',
          mine: false,
          timeLabel: '10:03',
          attachment: const TimelineAttachment(
            id: 'video',
            kind: TimelineAttachmentKind.video,
            name: 'clip.mp4',
            sizeLabel: '8 MB · Video',
          ),
        ),
      ];

      final model = ThreadMediaViewerModel.fromReplies(
        roomId: 'alice',
        parent: parent,
        replies: replies,
        initialReplyId: 'video-reply',
        actionPort: actionPort,
      );

      expect(model.items.map((item) => item.id), <String>[
        'image-reply',
        'video-reply',
      ]);
      expect(model.initialIndex, 1);
      expect(model.items.last.caption?.toPlainText(), 'Video caption');

      await model.onSave(model.items.first);
      await model.onShare(model.items.last);

      expect(actionPort.calls, <
        ({String action, String roomId, String parentEventId, String replyId})
      >[
        (
          action: 'save',
          roomId: 'alice',
          parentEventId: 'parent',
          replyId: 'image-reply',
        ),
        (
          action: 'share',
          roomId: 'alice',
          parentEventId: 'parent',
          replyId: 'video-reply',
        ),
      ]);
    },
  );

  testWidgets(
    'thread media viewer preserves thread geometry across a 120 Hz round trip',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      threadController.reset(sendPort: const DeterministicThreadSendPort());
      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final seededReplies = threadController
          .repliesFor(roomId: 'alice', parent: parent)
          .value;
      threadController.applyThreadSnapshot(
        roomId: 'alice',
        parent: parent,
        replies: <ThreadReply>[
          seededReplies[0],
          seededReplies[1],
          ThreadReply(
            id: 'alice-98-thread-2',
            sender: 'Alice',
            body: 'Done — the latest update is ready to review.',
            mine: false,
            timeLabel: '10:24',
            attachment: const TimelineAttachment(
              id: 'thread-review-image',
              kind: TimelineAttachmentKind.image,
              name: 'review.png',
              sizeLabel: '1.8 MB · Photo',
            ),
          ),
        ],
        hasMore: true,
        unreadCount: 2,
        latestReadReplyId: seededReplies.first.id,
      );
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('thread-panel'));
      final list = find.byKey(const Key('thread-reply-list'));
      final mediaOpen = find.byKey(
        const Key('message-attachment-open-thread-alice-98-thread-2'),
      );
      expect(mediaOpen, findsOneWidget);
      expect(tester.widget<InkWell>(mediaOpen).onTap, isNotNull);
      await tester.ensureVisible(mediaOpen);
      await tester.pump();
      expect(mediaOpen.hitTestable(), findsOneWidget);
      final panelRect = _rectOf(tester, panel);
      final listRect = _rectOf(tester, list);

      await tester.tap(mediaOpen);
      await tester.pumpAndSettle();
      final viewer = find.byKey(const Key('media-viewer'));
      expect(viewer, findsOneWidget);
      final viewerSize = _rectOf(tester, viewer).size;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, viewer).size, viewerSize);
        expect(tester.takeException(), isNull);
      }

      expect(find.text('1 of 1'), findsOneWidget);
      expect(
        tester
            .widget<RichText>(find.byKey(const Key('media-caption')))
            .text
            .toPlainText(),
        'Done — the latest update is ready to review.',
      );
      expect(
        find.byKey(const Key('media-full-alice-98-thread-2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('media-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('media-viewer')), findsNothing);
      expect(_rectOf(tester, panel), panelRect);
      expect(_rectOf(tester, list), listRect);
      expect(
        find.byKey(const Key('thread-reply-alice-98-thread-2')),
        findsOneWidget,
      );
    },
  );
}
