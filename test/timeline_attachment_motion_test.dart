import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets(
    'attachment preview preserves settled composer geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      final messageList = find.byKey(const Key('message-list'));
      final initialList = _rectOf(tester, messageList);

      await tester.tap(find.byKey(const Key('composer-attach')));
      await tester.pumpAndSettle();
      expect(_rectOf(tester, messageList), initialList);
      await tester.tap(
        find.byKey(const Key('attachment-option-document-file')),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(const Key('composer-attachment-preview'));
      final composer = find.byKey(const Key('composer'));
      final previewRect = _rectOf(tester, preview);
      final composerRect = _rectOf(tester, composer);
      final listRect = _rectOf(tester, messageList);
      expect(previewRect.height, 68);
      expect(composerRect.height, greaterThan(76));
      expect(listRect.top, initialList.top);
      expect(listRect.width, initialList.width);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, preview), previewRect);
        expect(_rectOf(tester, composer), composerRect);
        expect(_rectOf(tester, messageList), listRect);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('timeline media viewer preserves source geometry at 120 Hz', (
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
        id: 'motion-viewer-image',
        kind: TimelineAttachmentKind.image,
        name: 'motion.jpg',
        sizeLabel: '3.4 MB · Photo',
      ),
      caption: 'Stable media transition',
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('message-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(scrollable);
    final source = find.byKey(Key('message-attachment-${message.id}'));
    final open = find.byKey(Key('message-attachment-open-${message.id}'));
    final initialList = _rectOf(tester, list);
    final initialSource = _rectOf(tester, source);
    final initialOffset = scrollState.position.pixels;

    await tester.tap(open);
    await tester.pump();
    await tester.pump(PerformanceContract.motionFrame);

    final viewer = find.byKey(const Key('media-viewer'));
    final pageView = find.byKey(const Key('media-page-view'));
    expect(viewer, findsOneWidget);
    final viewerRect = _rectOf(tester, viewer);
    final pageRect = _rectOf(tester, pageView);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, viewer), viewerRect);
      expect(_rectOf(tester, pageView), pageRect);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('media-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer')), findsNothing);
    expect(scrollState.position.pixels, initialOffset);
    expect(_rectOf(tester, list), initialList);
    expect(_rectOf(tester, source), initialSource);
  });
}
