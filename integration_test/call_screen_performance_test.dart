import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_screen.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'incoming call accept and in-call controls have zero late Flutter frames',
    (tester) async {
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
      coordinator.registerIncomingCall(
        const MatrixRtcSessionDescriptor(
          callId: 'benchmark-call',
          roomId: '!dm:example.org',
          kind: KiteCallKind.video,
          scope: KiteCallScope.direct,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: KiteCallScreen(coordinator: coordinator, roomName: 'Alice'),
        ),
      );
      await tester.pumpAndSettle();

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(find.byKey(const Key('call-accept')));
          await tester.pump();
          await tester.pump();
          expect(find.byKey(const Key('call-controls')), findsOneWidget);

          await tester.tap(find.byKey(const Key('call-microphone')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('call-camera')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('call-participant-alice')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('call-hang-up')));
          await tester.pump();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(coordinator.phase.value, KiteCallPhase.ended);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['call_screen_controls'] = <String, dynamic>{
        'journey': 'incoming_accept_controls_hangup',
        'fixture': 'deterministic_matrixrtc_call_v1',
        ...result,
        'result': 'PASS',
      };
    },
  );
}
