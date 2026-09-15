import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_runtime.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hydrates continuation policy once per active MatrixRTC call', () async {
    final fixture = _fixture();
    final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);

    await fixture.coordinator.startDirectVoiceCall('!one:example.org');
    await runtime.hydrateActiveCall();
    await runtime.hydrateActiveCall();

    expect(
      fixture.gateway.invocations
          .where(
            (entry) =>
                entry.type == MatrixRtcInvocationType.continuationCapabilities,
          )
          .length,
      1,
    );

    await fixture.coordinator.hangUp();
    fixture.coordinator.clearEndedCall();
    await fixture.coordinator.startDirectVideoCall('!two:example.org');
    await runtime.hydrateActiveCall();

    expect(
      fixture.gateway.invocations
          .where(
            (entry) =>
                entry.type == MatrixRtcInvocationType.continuationCapabilities,
          )
          .length,
      2,
    );
  });

  test('app lifecycle never asks MatrixRTC for an unsupported state', () async {
    final fixture = _fixture();
    final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
    fixture.gateway.callContinuationCapabilities =
        const KiteCallContinuationCapabilities(background: true, locked: false);
    await fixture.coordinator.startDirectVoiceCall('!dm:example.org');

    expect(await runtime.handleAppState(KiteCallAppState.background), isTrue);
    expect(fixture.coordinator.appState.value, KiteCallAppState.background);
    expect(await runtime.handleAppState(KiteCallAppState.locked), isFalse);
    expect(fixture.coordinator.appState.value, KiteCallAppState.background);
    expect(
      fixture.gateway.invocations
          .where((entry) => entry.type == MatrixRtcInvocationType.setAppState)
          .map((entry) => entry.appState),
      <KiteCallAppState?>[KiteCallAppState.background],
    );
  });

  test(
    'network loss publishes reconnecting state and remains retryable',
    () async {
      final fixture = _fixture();
      final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
      await fixture.coordinator.startDirectVideoCall('!dm:example.org');

      expect(await runtime.handleConnectivity(false), isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.reconnecting);
      expect(
        fixture.coordinator.activity.value?.phase,
        KiteCallPhase.reconnecting,
      );

      fixture.gateway.failNextWith = StateError('transport not ready');
      await expectLater(runtime.handleConnectivity(true), throwsStateError);
      expect(fixture.coordinator.phase.value, KiteCallPhase.reconnecting);

      expect(await runtime.handleConnectivity(true), isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.active);
      expect(
        fixture.gateway.invocations
            .where((entry) => entry.type == MatrixRtcInvocationType.reconnect)
            .length,
        2,
      );
    },
  );

  test('audio focus changes remain applicable while reconnecting', () async {
    final fixture = _fixture();
    final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
    await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
    await runtime.handleConnectivity(false);

    expect(await runtime.handleAudioInterruption(true), isTrue);
    expect(fixture.coordinator.isMediaInterrupted.value, isTrue);
    expect(await runtime.handleAudioInterruption(false), isTrue);
    expect(fixture.coordinator.isMediaInterrupted.value, isFalse);
  });

  test(
    'stale background completion cannot leak into a replacement call',
    () async {
      final fixture = _fixture();
      final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
      await fixture.coordinator.startDirectVoiceCall('!one:example.org');
      fixture.gateway.holdNextAppState = true;

      final pendingBackground = runtime.handleAppState(
        KiteCallAppState.background,
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.hasHeldAppState, isTrue);

      await fixture.coordinator.hangUp();
      fixture.coordinator.clearEndedCall();
      fixture.gateway.holdNextStart = true;
      final replacement = fixture.coordinator.startDirectVideoCall(
        '!two:example.org',
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.hasHeldStart, isTrue);

      fixture.gateway.completeHeldAppState();
      expect(await pendingBackground, isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.connecting);
      expect(fixture.coordinator.appState.value, KiteCallAppState.foreground);

      fixture.gateway.completeHeldStart();
      await replacement;
      expect(fixture.coordinator.appState.value, KiteCallAppState.foreground);
    },
  );

  test(
    'stale audio interruption cannot leak into a replacement call',
    () async {
      final fixture = _fixture();
      final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
      await fixture.coordinator.startDirectVoiceCall('!one:example.org');
      fixture.gateway.holdNextMediaInterruption = true;

      final pendingInterruption = runtime.handleAudioInterruption(true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.hasHeldMediaInterruption, isTrue);

      await fixture.coordinator.hangUp();
      fixture.coordinator.clearEndedCall();
      fixture.gateway.holdNextStart = true;
      final replacement = fixture.coordinator.startDirectVideoCall(
        '!two:example.org',
      );
      await Future<void>.delayed(Duration.zero);

      fixture.gateway.completeHeldMediaInterruption();
      expect(await pendingInterruption, isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.connecting);
      expect(fixture.coordinator.isMediaInterrupted.value, isFalse);

      fixture.gateway.completeHeldStart();
      await replacement;
      expect(fixture.coordinator.isMediaInterrupted.value, isFalse);
    },
  );

  test(
    'stale reconnect completion cannot activate a replacement call',
    () async {
      final fixture = _fixture();
      final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);
      await fixture.coordinator.startDirectVoiceCall('!one:example.org');
      await runtime.handleConnectivity(false);
      fixture.gateway.holdNextReconnect = true;

      final pendingReconnect = runtime.handleConnectivity(true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.hasHeldReconnect, isTrue);

      await fixture.coordinator.hangUp();
      fixture.coordinator.clearEndedCall();
      fixture.gateway.holdNextStart = true;
      final replacement = fixture.coordinator.startDirectVideoCall(
        '!two:example.org',
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.coordinator.phase.value, KiteCallPhase.connecting);

      fixture.gateway.completeHeldReconnect();
      expect(await pendingReconnect, isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.connecting);
      expect(fixture.coordinator.activity.value, isNull);

      fixture.gateway.completeHeldStart();
      await replacement;
      expect(fixture.coordinator.phase.value, KiteCallPhase.active);
      expect(fixture.coordinator.session.value?.roomId, '!two:example.org');
    },
  );

  test('runtime events are ignored when there is no running call', () async {
    final fixture = _fixture();
    final runtime = KiteCallRuntimeCoordinator(fixture.coordinator);

    expect(await runtime.handleAppState(KiteCallAppState.background), isFalse);
    expect(await runtime.handleAudioInterruption(true), isFalse);
    expect(await runtime.handleConnectivity(false), isFalse);
    expect(fixture.gateway.invocations, isEmpty);
  });

  test(
    'Flutter lifecycle binding maps foreground and background states',
    () async {
      final fixture = _fixture();
      fixture.gateway.callContinuationCapabilities =
          const KiteCallContinuationCapabilities(
            background: true,
            locked: true,
          );
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
      final binding = KiteCallRuntimeBinding(
        runtime: KiteCallRuntimeCoordinator(fixture.coordinator),
      );

      expect(
        KiteCallRuntimeBinding.mapLifecycleState(AppLifecycleState.resumed),
        KiteCallAppState.foreground,
      );
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(
          KiteCallRuntimeBinding.mapLifecycleState(state),
          KiteCallAppState.background,
        );
      }

      expect(
        await binding.handleLifecycleState(AppLifecycleState.paused),
        isTrue,
      );
      expect(fixture.coordinator.appState.value, KiteCallAppState.background);
      expect(
        await binding.handleLifecycleState(AppLifecycleState.resumed),
        isTrue,
      );
      expect(fixture.coordinator.appState.value, KiteCallAppState.foreground);
      expect(await binding.handleDeviceLocked(), isTrue);
      expect(fixture.coordinator.appState.value, KiteCallAppState.locked);
    },
  );

  test(
    'runtime binding keeps unsupported lock state out of MatrixRTC',
    () async {
      final fixture = _fixture();
      fixture.gateway.callContinuationCapabilities =
          const KiteCallContinuationCapabilities(
            background: true,
            locked: false,
          );
      await fixture.coordinator.startDirectVideoCall('!dm:example.org');
      final binding = KiteCallRuntimeBinding(
        runtime: KiteCallRuntimeCoordinator(fixture.coordinator),
      );

      expect(await binding.handleDeviceLocked(), isFalse);
      expect(fixture.coordinator.appState.value, KiteCallAppState.foreground);
      expect(
        fixture.gateway.invocations.where(
          (entry) => entry.type == MatrixRtcInvocationType.setAppState,
        ),
        isEmpty,
      );
    },
  );
}

_CallRuntimeFixture _fixture() {
  final gateway = DeterministicMatrixRtcGateway();
  final coordinator = KiteCallCoordinator(
    gateway: gateway,
    pictureInPicture: DeterministicPictureInPicturePort(),
    logger: StructuredLogger(
      sink: MemoryStructuredLogSink(),
      traceIds: SequenceTraceIdGenerator(seed: 700),
    ),
  );
  return _CallRuntimeFixture(gateway: gateway, coordinator: coordinator);
}

final class _CallRuntimeFixture {
  const _CallRuntimeFixture({required this.gateway, required this.coordinator});

  final DeterministicMatrixRtcGateway gateway;
  final KiteCallCoordinator coordinator;
}
