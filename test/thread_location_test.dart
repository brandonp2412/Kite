import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      locationPort: DeterministicThreadLocationPort(),
    );
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets(
    'thread composer shares static location and hides live location',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final port = DeterministicThreadLocationPort(latency: Duration.zero);
      threadController.reset(
        sendPort: const DeterministicThreadSendPort(latency: Duration.zero),
        locationPort: port,
      );
      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');

      await tester.tap(find.byKey(const Key('thread-composer-attach')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('attachment-option-location')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('attachment-option-live-location')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('attachment-option-location')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('location-share-sheet')), findsOneWidget);
      expect(find.text('Britomart'), findsOneWidget);
      await tester.tap(find.byKey(const Key('location-share-confirm')));
      await tester.pumpAndSettle();

      final reply = threadController
          .repliesFor(roomId: 'alice', parent: parent)
          .value
          .last;
      expect(reply.location?.kind, TimelineLocationKind.staticLocation);
      expect(reply.location?.label, 'Britomart');
      expect(reply.sendState.value, TimelineSendState.sent);
      expect(port.sentLocations, hasLength(1));
      expect(port.sentLocations.single.parentEventId, parent.id);
      expect(
        find.byKey(Key('message-location-thread-${reply.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'static thread location share keeps shell geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      threadController.reset(
        sendPort: const DeterministicThreadSendPort(latency: Duration.zero),
        locationPort: DeterministicThreadLocationPort(latency: Duration.zero),
      );
      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('thread-header'));
      final composer = find.byKey(const Key('thread-composer'));
      final list = find.byKey(const Key('thread-reply-list'));
      final headerRect = tester.getRect(header);
      final composerRect = tester.getRect(composer);
      final listRect = tester.getRect(list);

      await tester.tap(find.byKey(const Key('thread-composer-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('attachment-option-location')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(header), headerRect);
        expect(tester.getRect(composer), composerRect);
        expect(tester.getRect(list), listRect);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('location-share-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('location-share-confirm')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(tester.getRect(header), headerRect);
        expect(tester.getRect(composer), composerRect);
        expect(tester.getRect(list), listRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('location-share-sheet')), findsNothing);
      expect(
        find.byKey(const Key('message-location-thread-kite-thread-0')),
        findsOneWidget,
      );
    },
  );
}
