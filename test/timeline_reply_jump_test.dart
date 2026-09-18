import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets(
    'reply preview jumps to its referenced event without resizing the timeline',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      selectRoom('alice');
      final messages = timelineController.messagesFor('alice').value;
      final target = messages[12];
      final reply = timelineController.sendText(
        'alice',
        'Reply that links back to history',
        replyTo: target,
      );

      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('message-list'));
      final replyPreview = find.byKey(Key('reply-preview-${reply.id}'));
      final targetRow = find.byKey(Key('message-row-${target.id}'));
      final listRect = tester.getRect(list);

      expect(replyPreview, findsOneWidget);
      expect(
        find.ancestor(
          of: replyPreview,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Jump to replied message',
          ),
        ),
        findsOneWidget,
      );
      expect(targetRow, findsNothing);

      await tester.tap(replyPreview);
      await tester.pump();

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(list), listRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      expect(targetRow, findsOneWidget);
      expect(find.byKey(Key('focused-message-${target.id}')), findsOneWidget);
      final targetRect = tester.getRect(targetRow);
      expect(targetRect.bottom, greaterThan(listRect.top));
      expect(targetRect.top, lessThan(listRect.bottom));
      expect(tester.getRect(list), listRect);
    },
  );
}
