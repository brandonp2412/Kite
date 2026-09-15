import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/media/room_content_gallery.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals.dart';

List<TimelineMessage> _messages() => <TimelineMessage>[
  TimelineMessage(
    id: 'link-message',
    sender: 'Maya',
    body: 'Reference https://matrix.org/docs/.',
    mine: false,
    timeLabel: '09:12',
  ),
  TimelineMessage(
    id: 'photo-message',
    sender: 'Maya',
    body: 'Harbour review',
    mine: false,
    timeLabel: '09:18',
    attachment: const TimelineAttachment(
      id: 'photo',
      kind: TimelineAttachmentKind.image,
      name: 'harbour.jpg',
      sizeLabel: '2.4 MB · Photo',
    ),
  ),
  TimelineMessage(
    id: 'file-message',
    sender: 'You',
    body: '',
    mine: true,
    timeLabel: '09:22',
    attachment: const TimelineAttachment(
      id: 'file',
      kind: TimelineAttachmentKind.file,
      name: 'release-notes.pdf',
      sizeLabel: '840 KB · PDF',
    ),
  ),
  TimelineMessage(
    id: 'video-message',
    sender: 'Noah',
    body: 'Motion pass',
    mine: false,
    timeLabel: '09:27',
    attachment: const TimelineAttachment(
      id: 'video',
      kind: TimelineAttachmentKind.video,
      name: 'motion.mp4',
      sizeLabel: '18.2 MB · Video',
    ),
  ),
];

void main() {
  test('extracts normalized links from visible messages', () {
    final links = roomContentLinks(_messages());
    expect(links, hasLength(1));
    expect(links.single.url.toString(), 'https://matrix.org/docs/');
    expect(links.single.sender, 'Maya');
  });

  testWidgets('media files and links stay scoped to their gallery tabs', (
    tester,
  ) async {
    final messages = signal<List<TimelineMessage>>(_messages());
    Uri? openedLink;
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: RoomContentGallery(
          roomId: 'design',
          messages: messages,
          onOpenLink: (uri) => openedLink = uri,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-content-media-grid')), findsOneWidget);
    expect(
      find.byKey(const Key('room-content-media-photo-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('room-content-media-video-message')),
      findsOneWidget,
    );
    expect(find.text('release-notes.pdf'), findsNothing);

    await tester.tap(find.byKey(const Key('room-content-media-video-message')));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewer), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('media-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-content-tab-files')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('room-content-file-file-message')),
      findsOneWidget,
    );
    expect(find.text('release-notes.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-content-tab-links')));
    await tester.pumpAndSettle();
    expect(find.text('matrix.org'), findsOneWidget);
    await tester.tap(find.byKey(const Key('room-content-link-link-message-0')));
    await tester.pump();
    expect(openedLink.toString(), 'https://matrix.org/docs/');
  });

  testWidgets('live message updates populate the active empty tab in place', (
    tester,
  ) async {
    final messages = signal<List<TimelineMessage>>(const <TimelineMessage>[]);
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: RoomContentGallery(roomId: 'design', messages: messages),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-content-empty-media')), findsOneWidget);
    messages.value = _messages();
    await tester.pump();

    expect(find.byKey(const Key('room-content-media-grid')), findsOneWidget);
    expect(find.byKey(const Key('room-content-empty-media')), findsNothing);
  });
}
