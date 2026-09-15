import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  setUp(() {
    selectRoom('alice');
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
  });

  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  for (final (name, theme) in <(String, ThemeData)>[
    ('light', KiteTheme.light),
    ('dark', KiteTheme.dark),
  ]) {
    testWidgets('Matrix projected timeline $name reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.applyMatrixEvents('alice', <MatrixTimelineEvent>[
        _event(
          eventId: r'$matrix-text',
          streamPosition: 1,
          senderId: '@alice:example.org',
          msgtype: 'm.text',
          body: 'Matrix sync keeps the visible timeline anchored.',
        ),
        _event(
          eventId: r'$matrix-audio',
          streamPosition: 2,
          senderId: '@alice:example.org',
          msgtype: 'm.audio',
          body: 'Planning notes.m4a',
          info: const <String, Object?>{
            'size': 2200000,
            'duration': 65000,
            'mimetype': 'audio/mp4',
          },
        ),
        _event(
          eventId: r'$matrix-voice',
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
      ], currentUserId: '@me:example.org');

      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('timeline-stack')),
        matchesGoldenFile('goldens/matrix_timeline_projection_$name.png'),
      );
    });
  }
}

MatrixTimelineEvent _event({
  required String eventId,
  required int streamPosition,
  required String senderId,
  required String msgtype,
  required String body,
  Map<String, Object?>? info,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return MatrixTimelineEvent(
    eventId: eventId,
    roomId: 'alice',
    senderId: senderId,
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(
      2026,
      9,
      16,
      10,
    ).add(Duration(minutes: streamPosition)),
    streamPosition: streamPosition,
    content: <String, Object?>{
      'msgtype': msgtype,
      'body': body,
      'info': ?info,
      ...extra,
    },
  );
}
