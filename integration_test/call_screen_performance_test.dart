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

  testWidgets('incoming call accept has zero late Flutter frames', (
    tester,
  ) async {
    final fixture = _fixture();
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'benchmark-call',
        roomId: '!dm:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.direct,
      ),
    );
    await _pumpCall(tester, fixture.coordinator);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('call-accept')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('call-controls')), findsOneWidget);
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(fixture.coordinator.phase.value, KiteCallPhase.active);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['incoming_call_accept'] = <String, dynamic>{
      'journey': 'incoming_call_accept',
      'fixture': 'deterministic_matrixrtc_call_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('remote active-call end has zero late Flutter frames', (
    tester,
  ) async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');
    final callId = fixture.coordinator.session.value!.callId;
    await _pumpCall(tester, fixture.coordinator);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        expect(fixture.coordinator.endCallFromSync(callId), isTrue);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('call-ended')), findsOneWidget);
        expect(find.text('Call ended'), findsOneWidget);
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['remote_call_end'] = <String, dynamic>{
      'journey': 'remote_active_call_end',
      'fixture': 'deterministic_matrixrtc_call_v2_sync_lifetime',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('active call controls have zero late Flutter frames', (
    tester,
  ) async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');
    await fixture.coordinator.refreshParticipants();
    await fixture.coordinator.refreshAudioRoutes();
    await fixture.coordinator.refreshPictureInPictureSupport();
    await _pumpCall(tester, fixture.coordinator);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(_roundButton('call-microphone'));
        await tester.pumpAndSettle();
        await tester.tap(_roundButton('call-camera'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('call-participant-alice')));
        await tester.pumpAndSettle();
        await tester.tap(_roundButton('call-hang-up'));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['call_controls'] = <String, dynamic>{
      'journey': 'active_call_controls_hangup',
      'fixture': 'deterministic_matrixrtc_call_v1',
      ...result,
      'result': 'PASS',
    };
  });
}

_CallFixture _fixture() {
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
  return _CallFixture(gateway: gateway, coordinator: coordinator);
}

Future<void> _pumpCall(
  WidgetTester tester,
  KiteCallCoordinator coordinator,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KiteTheme.light,
      home: KiteCallScreen(coordinator: coordinator, roomName: 'Alice'),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _roundButton(String key) => find.byKey(Key(key));

final class _CallFixture {
  const _CallFixture({required this.gateway, required this.coordinator});

  final DeterministicMatrixRtcGateway gateway;
  final KiteCallCoordinator coordinator;
}
