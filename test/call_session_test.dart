import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

void main() {
  test(
    'starts direct voice and video calls through the MatrixRTC boundary',
    () async {
      final voice = _fixture(seed: 10);
      await voice.coordinator.startDirectVoiceCall('!dm:example.org');

      expect(voice.coordinator.phase.value, KiteCallPhase.active);
      expect(voice.coordinator.isVideo.value, isFalse);
      expect(voice.coordinator.isGroupCall.value, isFalse);
      expect(voice.coordinator.session.value?.callId, 'call-11');
      expect(voice.coordinator.session.value?.kind, KiteCallKind.voice);
      expect(voice.coordinator.session.value?.scope, KiteCallScope.direct);
      expect(
        voice.gateway.invocations.single.type,
        MatrixRtcInvocationType.start,
      );
      expect(
        voice.gateway.invocations.single.launchConfig?.intent,
        MatrixRtcLaunchIntent.startCallDmVoice,
      );
      expect(
        voice.gateway.invocations.single.launchConfig?.intent.elementCallValue,
        'start_call_dm_voice',
      );
      expect(
        voice.gateway.invocations.single.launchConfig?.perParticipantE2ee,
        isTrue,
      );
      expect(
        voice.gateway.invocations.single.launchConfig?.controlledAudioDevices,
        isTrue,
      );

      final video = _fixture(seed: 20);
      await video.coordinator.startDirectVideoCall('!dm:example.org');

      expect(video.coordinator.phase.value, KiteCallPhase.active);
      expect(video.coordinator.isVideo.value, isTrue);
      expect(video.coordinator.isGroupCall.value, isFalse);
      expect(video.coordinator.session.value?.callId, 'call-21');
      expect(video.coordinator.session.value?.kind, KiteCallKind.video);
      expect(video.coordinator.session.value?.scope, KiteCallScope.direct);
      expect(
        video.gateway.invocations.single.launchConfig?.intent,
        MatrixRtcLaunchIntent.startCallDm,
      );
    },
  );

  test('starts and joins group calls without inventing call crypto', () async {
    final started = _fixture(seed: 30);
    await started.coordinator.startGroupCall(
      '!group:example.org',
      kind: KiteCallKind.voice,
    );

    expect(started.coordinator.phase.value, KiteCallPhase.active);
    expect(started.coordinator.isVideo.value, isFalse);
    expect(started.coordinator.isGroupCall.value, isTrue);
    expect(started.coordinator.session.value?.callId, 'call-31');
    expect(started.coordinator.session.value?.scope, KiteCallScope.group);
    expect(
      started.gateway.invocations.single.launchConfig?.intent,
      MatrixRtcLaunchIntent.startCallVoice,
    );

    final joined = _fixture();
    await joined.coordinator.joinGroupCall(
      roomId: '!group:example.org',
      callId: 'element-call-session',
    );

    expect(joined.coordinator.phase.value, KiteCallPhase.active);
    expect(joined.coordinator.isVideo.value, isTrue);
    expect(joined.coordinator.isGroupCall.value, isTrue);
    expect(joined.coordinator.session.value?.callId, 'element-call-session');
    expect(
      joined.gateway.invocations.single.type,
      MatrixRtcInvocationType.joinGroup,
    );
    expect(
      joined.gateway.invocations.single.launchConfig?.intent,
      MatrixRtcLaunchIntent.joinExisting,
    );
  });

  test('accepts an incoming call and hangs up through the gateway', () async {
    final fixture = _fixture();
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'incoming-1',
        roomId: '!dm:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.direct,
      ),
    );

    expect(fixture.coordinator.phase.value, KiteCallPhase.ringing);
    expect(fixture.coordinator.isVideo.value, isTrue);

    await fixture.coordinator.acceptIncomingCall();
    expect(fixture.coordinator.phase.value, KiteCallPhase.active);

    await fixture.coordinator.hangUp();
    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.hungUp,
    );
    expect(
      fixture.gateway.invocations.map((entry) => entry.type),
      <MatrixRtcInvocationType>[
        MatrixRtcInvocationType.accept,
        MatrixRtcInvocationType.hangUp,
      ],
    );
  });

  test('declines an incoming call and can clear the ended state', () async {
    final fixture = _fixture();
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'incoming-2',
        roomId: '!dm:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      ),
    );

    await fixture.coordinator.declineIncomingCall();

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.declined,
    );
    expect(
      fixture.gateway.invocations.single.type,
      MatrixRtcInvocationType.decline,
    );

    fixture.coordinator.clearEndedCall();
    expect(fixture.coordinator.phase.value, KiteCallPhase.idle);
    expect(fixture.coordinator.session.value, isNull);
    expect(fixture.coordinator.isVideo.value, isFalse);
    expect(fixture.coordinator.isGroupCall.value, isFalse);
  });

  test(
    'clears ended call identity before a replacement call connects',
    () async {
      final fixture = _fixture(seed: 50);
      await fixture.coordinator.startDirectVoiceCall('!first:example.org');
      await fixture.coordinator.hangUp();

      fixture.gateway.holdNextStart = true;
      final replacement = fixture.coordinator.startDirectVideoCall(
        '!second:example.org',
      );

      expect(fixture.gateway.hasHeldStart, isTrue);
      expect(fixture.coordinator.phase.value, KiteCallPhase.connecting);
      expect(fixture.coordinator.session.value, isNull);
      expect(fixture.coordinator.isVideo.value, isTrue);
      expect(fixture.coordinator.isGroupCall.value, isFalse);

      fixture.gateway.completeHeldStart();
      await replacement;

      expect(fixture.coordinator.phase.value, KiteCallPhase.active);
      expect(fixture.coordinator.session.value?.callId, 'call-52');
      expect(fixture.coordinator.session.value?.roomId, '!second:example.org');
    },
  );

  test('rejects overlapping calls before touching MatrixRTC', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVoiceCall('!first:example.org');

    await expectLater(
      fixture.coordinator.startDirectVideoCall('!second:example.org'),
      throwsStateError,
    );

    expect(fixture.gateway.invocations, hasLength(1));
    expect(fixture.coordinator.session.value?.roomId, '!first:example.org');
  });

  test(
    'microphone mute delegates only real state changes to MatrixRTC',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');

      await fixture.coordinator.setMicrophoneMuted(true);
      await fixture.coordinator.setMicrophoneMuted(true);
      await fixture.coordinator.setMicrophoneMuted(false);

      expect(fixture.coordinator.isMicrophoneMuted.value, isFalse);
      expect(
        fixture.gateway.invocations
            .where(
              (entry) =>
                  entry.type == MatrixRtcInvocationType.setMicrophoneMuted,
            )
            .map((entry) => entry.enabled),
        <bool?>[true, false],
      );
    },
  );

  test('failed microphone mute preserves the last confirmed state', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
    fixture.gateway.failNextWith = StateError('media failed');

    await expectLater(
      fixture.coordinator.setMicrophoneMuted(true),
      throwsStateError,
    );

    expect(fixture.coordinator.isMicrophoneMuted.value, isFalse);
  });

  test(
    'video controls delegate enable and camera switching to MatrixRTC',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVideoCall('!dm:example.org');

      expect(fixture.coordinator.isCameraEnabled.value, isTrue);
      expect(fixture.coordinator.cameraFacing.value, KiteCameraFacing.front);

      await fixture.coordinator.setCameraEnabled(false);
      expect(fixture.coordinator.isCameraEnabled.value, isFalse);
      await expectLater(fixture.coordinator.switchCamera(), throwsStateError);

      await fixture.coordinator.setCameraEnabled(true);
      await fixture.coordinator.switchCamera();

      expect(fixture.coordinator.isCameraEnabled.value, isTrue);
      expect(fixture.coordinator.cameraFacing.value, KiteCameraFacing.rear);
      expect(
        fixture.gateway.invocations
            .where(
              (entry) =>
                  entry.type == MatrixRtcInvocationType.setCameraEnabled ||
                  entry.type == MatrixRtcInvocationType.switchCamera,
            )
            .map((entry) => entry.type),
        <MatrixRtcInvocationType>[
          MatrixRtcInvocationType.setCameraEnabled,
          MatrixRtcInvocationType.setCameraEnabled,
          MatrixRtcInvocationType.switchCamera,
        ],
      );
    },
  );

  test(
    'camera controls reject voice calls before touching MatrixRTC',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
      final invocationCount = fixture.gateway.invocations.length;

      await expectLater(
        fixture.coordinator.setCameraEnabled(true),
        throwsStateError,
      );
      await expectLater(fixture.coordinator.switchCamera(), throwsStateError);

      expect(fixture.gateway.invocations, hasLength(invocationCount));
    },
  );

  test(
    'audio routes refresh and selection preserve platform route identity',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');

      final routes = await fixture.coordinator.refreshAudioRoutes();
      expect(routes.map((route) => route.id), <String>['system', 'speaker']);
      expect(
        () => routes.add(
          const KiteAudioRoute(
            id: 'invalid',
            label: 'Invalid',
            kind: KiteAudioRouteKind.other,
          ),
        ),
        throwsUnsupportedError,
      );

      await fixture.coordinator.selectAudioRoute('speaker');
      await fixture.coordinator.selectAudioRoute('speaker');
      expect(fixture.coordinator.selectedAudioRouteId.value, 'speaker');
      expect(
        fixture.gateway.invocations
            .where(
              (entry) => entry.type == MatrixRtcInvocationType.selectAudioRoute,
            )
            .map((entry) => entry.routeId),
        <String?>['speaker'],
      );

      await expectLater(
        fixture.coordinator.selectAudioRoute('missing'),
        throwsStateError,
      );

      fixture.gateway.audioRoutes = const <KiteAudioRoute>[
        KiteAudioRoute(
          id: 'system',
          label: 'System default',
          kind: KiteAudioRouteKind.systemDefault,
        ),
      ];
      await fixture.coordinator.refreshAudioRoutes();
      expect(fixture.coordinator.selectedAudioRouteId.value, isNull);
    },
  );

  test(
    'audio interruption state follows only confirmed MatrixRTC media changes',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');

      await fixture.coordinator.setMediaInterrupted(true);
      await fixture.coordinator.setMediaInterrupted(true);
      expect(fixture.coordinator.isMediaInterrupted.value, isTrue);

      fixture.gateway.failNextWith = StateError('audio focus failed');
      await expectLater(
        fixture.coordinator.setMediaInterrupted(false),
        throwsStateError,
      );
      expect(fixture.coordinator.isMediaInterrupted.value, isTrue);

      await fixture.coordinator.setMediaInterrupted(false);
      expect(fixture.coordinator.isMediaInterrupted.value, isFalse);
      expect(
        fixture.gateway.invocations
            .where(
              (entry) =>
                  entry.type == MatrixRtcInvocationType.setMediaInterrupted,
            )
            .map((entry) => entry.enabled),
        <bool?>[true, false, false],
      );
    },
  );

  test(
    'call activity exposes exact room call state through lifecycle transitions',
    () async {
      final fixture = _fixture();
      fixture.coordinator.registerIncomingCall(
        const MatrixRtcSessionDescriptor(
          callId: 'incoming-activity',
          roomId: '!room:example.org',
          kind: KiteCallKind.video,
          scope: KiteCallScope.group,
        ),
      );

      expect(fixture.coordinator.activity.value?.callId, 'incoming-activity');
      expect(fixture.coordinator.activity.value?.roomId, '!room:example.org');
      expect(fixture.coordinator.activity.value?.phase, KiteCallPhase.ringing);
      expect(fixture.coordinator.activity.value?.isActive, isTrue);

      await fixture.coordinator.acceptIncomingCall();
      expect(fixture.coordinator.activity.value?.phase, KiteCallPhase.active);

      await fixture.coordinator.hangUp();
      expect(fixture.coordinator.activity.value?.phase, KiteCallPhase.ended);
      expect(fixture.coordinator.activity.value?.isActive, isFalse);
      expect(
        fixture.coordinator.activity.value?.endReason,
        KiteCallEndReason.hungUp,
      );

      fixture.coordinator.clearEndedCall();
      expect(fixture.coordinator.activity.value, isNull);
    },
  );

  test(
    'background and lock continuation follows platform capabilities exactly',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
      fixture.gateway.callContinuationCapabilities =
          const KiteCallContinuationCapabilities(
            background: true,
            locked: false,
          );

      final capabilities = await fixture.coordinator
          .refreshContinuationCapabilities();
      expect(capabilities.background, isTrue);
      expect(capabilities.locked, isFalse);

      await fixture.coordinator.setAppState(KiteCallAppState.background);
      expect(fixture.coordinator.appState.value, KiteCallAppState.background);

      final invocationCount = fixture.gateway.invocations.length;
      await expectLater(
        fixture.coordinator.setAppState(KiteCallAppState.locked),
        throwsStateError,
      );
      expect(fixture.gateway.invocations, hasLength(invocationCount));
      expect(fixture.coordinator.appState.value, KiteCallAppState.background);

      await fixture.coordinator.setAppState(KiteCallAppState.foreground);
      expect(
        fixture.gateway.invocations
            .where((entry) => entry.type == MatrixRtcInvocationType.setAppState)
            .map((entry) => entry.appState),
        <KiteCallAppState?>[
          KiteCallAppState.background,
          KiteCallAppState.foreground,
        ],
      );
    },
  );

  test(
    'failed app-state transition preserves last confirmed lifecycle state',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
      await fixture.coordinator.refreshContinuationCapabilities();
      fixture.gateway.failNextWith = StateError('platform lifecycle failed');

      await expectLater(
        fixture.coordinator.setAppState(KiteCallAppState.background),
        throwsStateError,
      );

      expect(fixture.coordinator.appState.value, KiteCallAppState.foreground);
    },
  );

  test('transient reconnect remains retryable after failure and restores active state', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');
    fixture.gateway.failNextWith = StateError('network still unavailable');

    await expectLater(
      fixture.coordinator.reconnectAfterTransientNetworkLoss(),
      throwsStateError,
    );
    expect(fixture.coordinator.phase.value, KiteCallPhase.reconnecting);
    expect(fixture.coordinator.session.value?.roomId, '!dm:example.org');
    expect(
      fixture.coordinator.activity.value?.phase,
      KiteCallPhase.reconnecting,
    );

    await fixture.coordinator.reconnectAfterTransientNetworkLoss();
    expect(fixture.coordinator.phase.value, KiteCallPhase.active);
    expect(fixture.coordinator.activity.value?.phase, KiteCallPhase.active);
    expect(
      fixture.gateway.invocations
          .where((entry) => entry.type == MatrixRtcInvocationType.reconnect)
          .map((entry) => entry.callId),
      <String?>['call-1', 'call-1'],
    );
  });

  test('reconnecting calls can still hang up cleanly', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVoiceCall('!dm:example.org');
    fixture.gateway.failNextWith = StateError('offline');
    await expectLater(
      fixture.coordinator.reconnectAfterTransientNetworkLoss(),
      throwsStateError,
    );

    await fixture.coordinator.hangUp();

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.hungUp,
    );
  });

  test('gateway failures restore deterministic idle state and emit safe trace data', () async {
    final fixture = _fixture();
    fixture.gateway.failNextWith = StateError('transport failed');

    await expectLater(
      fixture.coordinator.startDirectVideoCall('!dm:example.org'),
      throwsStateError,
    );

    expect(fixture.coordinator.phase.value, KiteCallPhase.idle);
    expect(fixture.coordinator.session.value, isNull);
    expect(fixture.coordinator.isVideo.value, isFalse);
    expect(fixture.coordinator.isGroupCall.value, isFalse);
    expect(fixture.logs.events.map((event) => event.event), <DiagnosticEvent>[
      DiagnosticEvent.started,
      DiagnosticEvent.failed,
    ]);
    expect(
      fixture.logs.events.every((event) => event.flow == DiagnosticFlow.call),
      isTrue,
    );
  });
}

_CallFixture _fixture({int seed = 0}) {
  final gateway = DeterministicMatrixRtcGateway(seed: seed);
  final logs = MemoryStructuredLogSink();
  final coordinator = KiteCallCoordinator(
    gateway: gateway,
    logger: StructuredLogger(
      sink: logs,
      traceIds: SequenceTraceIdGenerator(seed: 100),
    ),
  );
  return _CallFixture(gateway: gateway, logs: logs, coordinator: coordinator);
}

final class _CallFixture {
  const _CallFixture({
    required this.gateway,
    required this.logs,
    required this.coordinator,
  });

  final DeterministicMatrixRtcGateway gateway;
  final MemoryStructuredLogSink logs;
  final KiteCallCoordinator coordinator;
}
