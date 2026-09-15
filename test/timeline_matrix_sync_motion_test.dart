import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  testWidgets(
    'synced message insertion preserves a retained scroll anchor at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);
      addTearDown(() {
        timelineController.reset(sendPort: DeterministicTimelineSendPort());
        selectRoom('kite');
      });

      selectRoom('alice');
      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final initial = <MatrixTimelineEvent>[
        for (var index = 0; index < 40; index++) _event(index),
      ];
      timelineController.applyMatrixEvents(
        'alice',
        initial,
        currentUserId: '@me:example.org',
      );

      await tester.pumpWidget(
        MaterialApp(theme: KiteTheme.light, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      final anchor = find.byKey(const Key(r'message-bubble-$matrix-20'));
      await tester.scrollUntilVisible(
        anchor,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('message-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(anchor, findsOneWidget);
      final before = tester.getRect(anchor);

      timelineController.applyMatrixEvents('alice', <MatrixTimelineEvent>[
        ...initial,
        _event(40),
      ], currentUserId: '@me:example.org');
      for (
        var sample = 0;
        sample < PerformanceContract.motionSamples;
        sample++
      ) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(anchor), before);
        expect(tester.takeException(), isNull);
      }

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('message-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.minScrollExtent);
      await tester.pump();
      expect(
        find.byKey(const Key(r'message-bubble-$matrix-40')),
        findsOneWidget,
      );
    },
  );
}

MatrixTimelineEvent _event(int index) {
  return MatrixTimelineEvent(
    eventId: '\$matrix-$index',
    roomId: 'alice',
    senderId: '@alice:example.org',
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(2026, 9, 16, 10, index),
    streamPosition: index,
    content: <String, Object?>{
      'msgtype': 'm.text',
      'body': 'Synced timeline message $index with stable geometry.',
    },
  );
}
