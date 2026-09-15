import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

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
    testWidgets('timeline audio and voice $name reference render', (
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
      final audio = timelineController.sendAttachment(
        'alice',
        const TimelineAttachment(
          id: 'golden-audio',
          kind: TimelineAttachmentKind.audio,
          name: 'Auckland night drive.m4a',
          sizeLabel: '3.8 MB · Audio',
          durationLabel: '03:42',
        ),
      );
      final voice = timelineController.sendAttachment(
        'alice',
        const TimelineAttachment(
          id: 'golden-voice',
          kind: TimelineAttachmentKind.voice,
          name: 'Voice message.ogg',
          sizeLabel: '268 KB · Voice',
          durationLabel: '00:18',
        ),
      );

      await tester.pumpWidget(KiteApp(themeMode: themeMode));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(Key('message-attachment-${audio.id}')),
        matchesGoldenFile('goldens/timeline_audio_card_$name.png'),
      );
      await expectLater(
        find.byKey(Key('message-attachment-${voice.id}')),
        matchesGoldenFile('goldens/timeline_voice_card_$name.png'),
      );
    });
  }
}
