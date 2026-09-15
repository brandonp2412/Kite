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
}
