import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets('media chrome animation preserves viewer geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: MediaViewer(items: fixture.items),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = find.byKey(const Key('media-viewer'));
    final pageView = find.byKey(const Key('media-page-view'));
    final topControls = find.byKey(const Key('media-top-controls'));
    final initialViewer = _rectOf(tester, viewer);
    final initialPageView = _rectOf(tester, pageView);
    final initialTopControls = _rectOf(tester, topControls);

    await tester.tap(find.byKey(const Key('media-gesture-surface')));

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, viewer), initialViewer);
      expect(_rectOf(tester, pageView), initialPageView);
      expect(_rectOf(tester, topControls), initialTopControls);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('adjacent-media swipe keeps fixed chrome geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: MediaViewer(items: fixture.items),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = find.byKey(const Key('media-viewer'));
    final topControls = find.byKey(const Key('media-top-controls'));
    final initialViewer = _rectOf(tester, viewer);
    final initialTopControls = _rectOf(tester, topControls);

    await tester.drag(
      find.byKey(const Key('media-page-view')),
      const Offset(-700, 0),
    );

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, viewer), initialViewer);
      expect(_rectOf(tester, topControls), initialTopControls);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
  });
}
