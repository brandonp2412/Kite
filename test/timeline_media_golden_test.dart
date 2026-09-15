import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/media/media_viewer.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final name = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('timeline media viewer $name reference render', (tester) async {
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
      final message = timelineController.sendAttachment(
        'alice',
        const TimelineAttachment(
          id: 'golden-harbour',
          kind: TimelineAttachmentKind.image,
          name: 'Auckland harbour.jpg',
          sizeLabel: '4.8 MB · Photo',
        ),
        caption: 'Auckland harbour · evening walk',
      );

      await tester.pumpWidget(KiteApp(themeMode: themeMode));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(Key('message-attachment-${message.id}')),
        matchesGoldenFile('goldens/timeline_media_card_$name.png'),
      );
      await tester.tap(
        find.byKey(Key('message-attachment-open-${message.id}')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MediaViewer), findsOneWidget);
      await expectLater(
        find.byKey(const Key('media-viewer')),
        matchesGoldenFile('goldens/timeline_media_viewer_$name.png'),
      );
    });
  }
}
