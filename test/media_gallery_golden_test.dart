import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/room_content_gallery.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals.dart';

List<TimelineMessage> _galleryMessages() => <TimelineMessage>[
  TimelineMessage(
    id: 'link',
    sender: 'Maya',
    body: 'Design notes https://matrix.org/docs/',
    mine: false,
    timeLabel: '09:12',
  ),
  TimelineMessage(
    id: 'photo-one',
    sender: 'Maya',
    body: 'Harbour',
    mine: false,
    timeLabel: '09:18',
    attachment: const TimelineAttachment(
      id: 'harbour',
      kind: TimelineAttachmentKind.image,
      name: 'harbour.jpg',
      sizeLabel: '2.4 MB · Photo',
    ),
  ),
  TimelineMessage(
    id: 'photo-two',
    sender: 'Noah',
    body: 'Trail',
    mine: false,
    timeLabel: '09:21',
    attachment: const TimelineAttachment(
      id: 'trail',
      kind: TimelineAttachmentKind.image,
      name: 'trail.jpg',
      sizeLabel: '3.1 MB · Photo',
    ),
  ),
  TimelineMessage(
    id: 'video',
    sender: 'Maya',
    body: 'Motion review',
    mine: false,
    timeLabel: '09:27',
    attachment: const TimelineAttachment(
      id: 'motion',
      kind: TimelineAttachmentKind.video,
      name: 'motion.mp4',
      sizeLabel: '18.2 MB · Video',
    ),
  ),
  TimelineMessage(
    id: 'file',
    sender: 'You',
    body: '',
    mine: true,
    timeLabel: '09:31',
    attachment: const TimelineAttachment(
      id: 'release-notes',
      kind: TimelineAttachmentKind.file,
      name: 'release-notes.pdf',
      sizeLabel: '840 KB · PDF',
    ),
  ),
];

void main() {
  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final name = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('shared content gallery $name reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: KiteTheme.light,
          darkTheme: KiteTheme.dark,
          themeMode: themeMode,
          home: RoomContentGallery(
            roomId: 'design',
            messages: signal<List<TimelineMessage>>(_galleryMessages()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('room-content-gallery')),
        matchesGoldenFile('goldens/media_gallery_$name.png'),
      );
    });
  }
}
