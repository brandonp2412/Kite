import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  testWidgets('audio and voice events render scoped playback controls', (
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
        id: 'audio-foundation',
        kind: TimelineAttachmentKind.audio,
        name: 'Night drive.m4a',
        sizeLabel: '3.8 MB · Audio',
        durationLabel: '03:42',
      ),
    );
    final voice = timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'voice-foundation',
        kind: TimelineAttachmentKind.voice,
        name: 'Voice message.ogg',
        sizeLabel: '268 KB · Voice',
        durationLabel: '00:18',
      ),
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('audio-toggle-${audio.id}')), findsOneWidget);
    expect(find.byKey(Key('audio-toggle-${voice.id}')), findsOneWidget);
    expect(
      find.byKey(Key('message-attachment-open-${audio.id}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('message-attachment-open-${voice.id}')),
      findsNothing,
    );
    expect(find.text('Night drive.m4a'), findsOneWidget);
    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('03:42'), findsOneWidget);
    expect(find.text('00:18'), findsOneWidget);

    await tester.tap(find.byKey(Key('audio-toggle-${audio.id}')));
    await tester.pump();
    expect(audio.audioPlaybackState.value, TimelineAudioPlaybackState.playing);
    expect(
      tester
          .widget<IconButton>(find.byKey(Key('audio-toggle-${audio.id}')))
          .tooltip,
      'Pause audio',
    );
    expect(voice.audioPlaybackState.value, TimelineAudioPlaybackState.paused);

    await tester.tap(find.byKey(Key('audio-toggle-${audio.id}')));
    await tester.pump();
    expect(audio.audioPlaybackState.value, TimelineAudioPlaybackState.paused);
  });

  test('audio and voice events never enter the visual media viewer model', () {
    final image = TimelineMessage(
      id: 'image-event',
      sender: 'Alice',
      body: '',
      mine: false,
      timeLabel: '10:00',
      attachment: const TimelineAttachment(
        id: 'image',
        kind: TimelineAttachmentKind.image,
        name: 'image.jpg',
        sizeLabel: '2 MB · Photo',
      ),
    );
    final audio = TimelineMessage(
      id: 'audio-event',
      sender: 'Alice',
      body: '',
      mine: false,
      timeLabel: '10:01',
      attachment: const TimelineAttachment(
        id: 'audio',
        kind: TimelineAttachmentKind.audio,
        name: 'track.m4a',
        sizeLabel: '4 MB · Audio',
        durationLabel: '02:31',
      ),
    );
    final voice = TimelineMessage(
      id: 'voice-event',
      sender: 'Alice',
      body: '',
      mine: false,
      timeLabel: '10:02',
      attachment: const TimelineAttachment(
        id: 'voice',
        kind: TimelineAttachmentKind.voice,
        name: 'voice.ogg',
        sizeLabel: '180 KB · Voice',
        durationLabel: '00:14',
      ),
    );

    final model = TimelineMediaViewerModel.fromMessages(
      roomId: 'alice',
      messages: <TimelineMessage>[image, audio, voice],
      initialMessageId: image.id,
    );

    expect(model.items.map((item) => item.id), <String>['image-event']);
  });

  testWidgets('audio playback toggle preserves timeline geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

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
        id: 'audio-motion',
        kind: TimelineAttachmentKind.audio,
        name: 'Stable audio.m4a',
        sizeLabel: '2.1 MB · Audio',
        durationLabel: '01:26',
      ),
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('message-list'));
    final card = find.byKey(Key('message-attachment-${message.id}'));
    final waveform = find.byKey(Key('audio-waveform-${message.id}'));
    final initialList = tester.getRect(list);
    final initialCard = tester.getRect(card);
    final initialWaveform = tester.getRect(waveform);

    await tester.tap(find.byKey(Key('audio-toggle-${message.id}')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(list), initialList);
      expect(tester.getRect(card), initialCard);
      expect(tester.getRect(waveform), initialWaveform);
      expect(tester.takeException(), isNull);
    }
    expect(
      message.audioPlaybackState.value,
      TimelineAudioPlaybackState.playing,
    );
  });
}
