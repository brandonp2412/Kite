import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_screen.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  testWidgets(
    'in-call control mutations preserve call shell geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final gateway = DeterministicMatrixRtcGateway()
        ..callParticipants = const <KiteCallParticipant>[
          KiteCallParticipant(
            participantId: 'alice',
            userId: '@alice:example.org',
            displayName: 'Alice',
            isLocal: false,
            isMicrophoneMuted: false,
            isCameraEnabled: true,
            isSpeaking: true,
          ),
          KiteCallParticipant(
            participantId: 'local',
            userId: '@me:example.org',
            displayName: 'Me',
            isLocal: true,
            isMicrophoneMuted: false,
            isCameraEnabled: true,
            isSpeaking: false,
          ),
        ];
      final coordinator = KiteCallCoordinator(
        gateway: gateway,
        pictureInPicture: DeterministicPictureInPicturePort(),
        logger: StructuredLogger(
          sink: MemoryStructuredLogSink(),
          traceIds: SequenceTraceIdGenerator(seed: 1),
        ),
      );
      await coordinator.startDirectVideoCall('!dm:example.org');

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: KiteCallScreen(coordinator: coordinator, roomName: 'Alice'),
        ),
      );
      await tester.pump();
      await tester.pump();

      final header = find.byKey(const Key('call-header'));
      final grid = find.byKey(const Key('call-participant-grid'));
      final controls = find.byKey(const Key('call-controls'));
      final headerRect = _rectOf(tester, header);
      final gridRect = _rectOf(tester, grid);
      final controlsRect = _rectOf(tester, controls);

      await tester.tap(find.byKey(const Key('call-microphone')));
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(_rectOf(tester, grid), gridRect);
        expect(_rectOf(tester, controls), controlsRect);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const Key('call-camera')));
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(_rectOf(tester, grid), gridRect);
        expect(_rectOf(tester, controls), controlsRect);
        expect(tester.takeException(), isNull);
      }

      gateway.callSecurityState = const KiteCallSecurityState(
        e2eeEnabled: true,
        identityTrust: KiteCallIdentityTrust.warning,
      );
      await coordinator.refreshSecurityState();
      for (var i = 0; i < PerformanceContract.motionSamples; i++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(_rectOf(tester, grid), gridRect);
        expect(_rectOf(tester, controls), controlsRect);
        expect(tester.takeException(), isNull);
      }
      expect(
        tester
            .widget<Tooltip>(
              find.descendant(
                of: find.byKey(const Key('call-security')),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        'Call security needs attention',
      );
    },
  );
}
