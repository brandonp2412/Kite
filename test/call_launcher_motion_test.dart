import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_launcher.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

void main() {
  testWidgets('call chooser preserves its source geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final coordinator = KiteCallCoordinator(
      gateway: DeterministicMatrixRtcGateway(),
      pictureInPicture: DeterministicPictureInPicturePort(),
      logger: StructuredLogger(
        sink: MemoryStructuredLogSink(),
        traceIds: SequenceTraceIdGenerator(seed: 910),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Alice'),
            actions: <Widget>[
              KiteRoomCallLauncher(
                coordinator: coordinator,
                roomId: '!dm:example.org',
                roomName: 'Alice',
                isDirect: true,
              ),
            ],
          ),
          body: const SizedBox.expand(key: Key('call-launch-background')),
        ),
      ),
    );

    final launcher = find.byKey(const Key('room-call-button'));
    final background = find.byKey(const Key('call-launch-background'));
    final launcherRect = tester.getRect(launcher);
    final backgroundRect = tester.getRect(background);

    await tester.tap(launcher);
    for (var i = 0; i < PerformanceContract.motionSamples; i++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(launcher), launcherRect);
      expect(tester.getRect(background), backgroundRect);
      expect(tester.takeException(), isNull);
    }
    expect(find.byKey(const Key('call-launch-sheet')), findsOneWidget);
  });
}
