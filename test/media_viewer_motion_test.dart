import 'dart:async';

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

  testWidgets('flick-to-dismiss reset is stable at 120 Hz', (tester) async {
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

    final pageView = find.byKey(const Key('media-page-view'));
    final topControls = find.byKey(const Key('media-top-controls'));
    final initialPageView = _rectOf(tester, pageView);
    final gesture = await tester.startGesture(tester.getCenter(pageView));
    await gesture.moveBy(const Offset(0, 48));
    await tester.pump(PerformanceContract.motionFrame);
    await gesture.moveBy(const Offset(0, 48));
    await tester.pump(PerformanceContract.motionFrame);

    final draggedPageView = _rectOf(tester, pageView);
    expect(draggedPageView.size, initialPageView.size);
    final draggedDistance = draggedPageView.top - initialPageView.top;
    expect(draggedDistance, greaterThan(0));
    expect(tester.widget<AnimatedOpacity>(topControls).opacity, 0);

    await gesture.up();
    var previousDistance = draggedDistance;
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      final frameRect = _rectOf(tester, pageView);
      expect(frameRect.size, initialPageView.size);
      final distance = (frameRect.top - initialPageView.top).abs();
      expect(distance, lessThanOrEqualTo(previousDistance + 0.01));
      previousDistance = distance;
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    expect(_rectOf(tester, pageView), initialPageView);
  });

  testWidgets('save progress preserves chrome geometry at 120 Hz', (
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
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: MediaViewer(
          items: fixture.items,
          onSave: (item) => completer.future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewer = find.byKey(const Key('media-viewer'));
    final topControls = find.byKey(const Key('media-top-controls'));
    final save = find.byKey(const Key('media-save'));
    final initialViewer = _rectOf(tester, viewer);
    final initialTopControls = _rectOf(tester, topControls);
    final initialSave = _rectOf(tester, save);

    await tester.tap(save);
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, viewer), initialViewer);
      expect(_rectOf(tester, topControls), initialTopControls);
      expect(_rectOf(tester, save), initialSave);
      expect(tester.takeException(), isNull);
    }
    expect(find.byKey(const Key('media-action-progress')), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(_rectOf(tester, viewer), initialViewer);
    expect(_rectOf(tester, topControls), initialTopControls);
    expect(_rectOf(tester, save), initialSave);
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
    expect(find.byKey(const Key('media-full-fixture-1')), findsOneWidget);
  });
}
