import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:kite/testing/deterministic_adapters.dart';

class _RecordingTimelineMediaActionPort implements TimelineMediaActionPort {
  final List<({String action, String roomId, String eventId})> calls =
      <({String action, String roomId, String eventId})>[];

  @override
  Future<void> save({
    required String roomId,
    required TimelineMessage message,
  }) async {
    calls.add((action: 'save', roomId: roomId, eventId: message.id));
  }

  @override
  Future<void> share({
    required String roomId,
    required TimelineMessage message,
  }) async {
    calls.add((action: 'share', roomId: roomId, eventId: message.id));
  }
}

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  testWidgets('timeline media visual renders downloaded image bytes', (
    tester,
  ) async {
    final provider = MemoryImage(DeterministicImageFixtures.transparentPng1x1);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 250,
            height: 132,
            child: TimelineMediaVisual(
              attachment: const TimelineAttachment(
                id: 'mxc://example.org/image',
                kind: TimelineAttachmentKind.image,
                name: 'image.png',
                sizeLabel: 'Image',
                contentUri: 'mxc://example.org/image',
              ),
              imageProvider: provider,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, same(provider));
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer previews, captions, and sends deterministic media', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-picker-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('attachment-option-photo-library')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-attachment-preview')),
      findsOneWidget,
    );
    expect(find.text('IMG_2048.jpg'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Screenshot from the latest build',
    );
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.attachment?.kind, TimelineAttachmentKind.image);
    expect(message.attachment?.name, 'IMG_2048.jpg');
    expect(message.body, 'Screenshot from the latest build');
    expect(find.byKey(const Key('composer-attachment-preview')), findsNothing);
    expect(find.byKey(Key('message-attachment-${message.id}')), findsOneWidget);
    expect(find.text('Screenshot from the latest build'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(message.sendState.value, TimelineSendState.sent);

    await tester.longPress(find.byKey(Key('message-bubble-${message.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-copy')), findsOneWidget);
    expect(find.text('Copy caption'), findsOneWidget);
  });

  testWidgets('attachment preview can be removed without sending', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    final initialCount = timelineController.messagesFor('alice').value.length;

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-document-file')));
    await tester.pumpAndSettle();
    expect(find.text('project-notes.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-attachment-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachment-preview')), findsNothing);
    expect(
      timelineController.messagesFor('alice').value,
      hasLength(initialCount),
    );
  });

  testWidgets('timeline media opens viewer and browses adjacent media only', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    final first = timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'viewer-image',
        kind: TimelineAttachmentKind.image,
        name: 'harbour.jpg',
        sizeLabel: '2.2 MB · Photo',
      ),
      caption: 'Harbour at dusk',
    );
    final second = timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'viewer-video',
        kind: TimelineAttachmentKind.video,
        name: 'walk.mp4',
        sizeLabel: '8.5 MB · Video',
      ),
      caption: 'Evening walk',
    );
    final file = timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'viewer-file',
        kind: TimelineAttachmentKind.file,
        name: 'notes.pdf',
        sizeLabel: '420 KB · PDF',
      ),
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('message-attachment-open-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('message-attachment-open-${second.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('message-attachment-open-${file.id}')), findsNothing);

    await tester.tap(find.byKey(Key('message-attachment-open-${first.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(
      tester
          .widget<RichText>(find.byKey(const Key('media-caption')))
          .text
          .toPlainText(),
      'Harbour at dusk',
    );
    expect(find.byKey(Key('media-full-${first.id}')), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('media-page-view')),
      const Offset(-520, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(
      tester
          .widget<RichText>(find.byKey(const Key('media-caption')))
          .text
          .toPlainText(),
      'Evening walk',
    );
    expect(find.byKey(Key('media-full-${second.id}')), findsOneWidget);
    expect(find.byKey(Key('media-full-${first.id}')), findsNothing);

    await tester.tap(find.byKey(const Key('media-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-viewer')), findsNothing);
  });

  test('timeline media actions stay scoped to their room and event', () async {
    final port = _RecordingTimelineMediaActionPort();
    final messages = <TimelineMessage>[
      TimelineMessage(
        id: 'image-event',
        sender: 'Alice',
        body: 'Image caption',
        mine: false,
        timeLabel: '10:00',
        attachment: const TimelineAttachment(
          id: 'image',
          kind: TimelineAttachmentKind.image,
          name: 'image.jpg',
          sizeLabel: '2 MB · Photo',
        ),
      ),
      TimelineMessage(
        id: 'file-event',
        sender: 'Alice',
        body: '',
        mine: false,
        timeLabel: '10:01',
        attachment: const TimelineAttachment(
          id: 'file',
          kind: TimelineAttachmentKind.file,
          name: 'notes.pdf',
          sizeLabel: '400 KB · PDF',
        ),
      ),
      TimelineMessage(
        id: 'video-event',
        sender: 'Alice',
        body: 'Video caption',
        mine: false,
        timeLabel: '10:02',
        attachment: const TimelineAttachment(
          id: 'video',
          kind: TimelineAttachmentKind.video,
          name: 'clip.mp4',
          sizeLabel: '8 MB · Video',
        ),
      ),
    ];
    final model = TimelineMediaViewerModel.fromMessages(
      roomId: 'alice',
      messages: messages,
      initialMessageId: 'image-event',
      actionPort: port,
    );

    expect(model.items.map((item) => item.id), <String>[
      'image-event',
      'video-event',
    ]);
    expect(model.initialIndex, 0);

    await model.onSave(model.items.first);
    await model.onShare(model.items.last);

    expect(port.calls, <({String action, String roomId, String eventId})>[
      (action: 'save', roomId: 'alice', eventId: 'image-event'),
      (action: 'share', roomId: 'alice', eventId: 'video-event'),
    ]);
  });
}
