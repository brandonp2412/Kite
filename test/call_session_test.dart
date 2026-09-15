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

  test('sync can end only the matching ringing incoming call as missed', () {
    final fixture = _fixture();
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'incoming-missed',
        roomId: '!dm:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      ),
    );

    expect(fixture.coordinator.endIncomingCallFromSync('other-call'), isFalse);
    expect(fixture.coordinator.phase.value, KiteCallPhase.ringing);

    expect(
      fixture.coordinator.endIncomingCallFromSync('incoming-missed'),
      isTrue,
    );
    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.missed,
    );
    expect(fixture.coordinator.activity.value?.isActive, isFalse);
    expect(fixture.gateway.invocations, isEmpty);
  });

  test('sync can end an active call without issuing a local hangup', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');
    final callId = fixture.coordinator.session.value!.callId;
    final invocationCount = fixture.gateway.invocations.length;

    expect(fixture.coordinator.endCallFromSync(callId), isTrue);

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.remoteEnded,
    );
    expect(fixture.coordinator.activity.value?.isActive, isFalse);
    expect(fixture.gateway.invocations, hasLength(invocationCount));
    expect(fixture.coordinator.endCallFromSync(callId), isFalse);
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

  test('call security state comes only from the MatrixRTC gateway and preserves last confirmed trust', () async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');
    fixture.gateway.callSecurityState = const KiteCallSecurityState(
      e2eeEnabled: true,
      identityTrust: KiteCallIdentityTrust.warning,
    );

    final security = await fixture.coordinator.refreshSecurityState();
    expect(security.e2eeEnabled, isTrue);
    expect(security.identityTrust, KiteCallIdentityTrust.warning);
    expect(security.hasTrustWarning, isTrue);
    expect(fixture.coordinator.securityState.value, same(security));

    fixture.gateway.callSecurityState = const KiteCallSecurityState(
      e2eeEnabled: true,
      identityTrust: KiteCallIdentityTrust.trusted,
    );
    fixture.gateway.failNextWith = StateError('security state unavailable');
    await expectLater(
      fixture.coordinator.refreshSecurityState(),
      throwsStateError,
    );

    expect(
      fixture.coordinator.securityState.value?.identityTrust,
      KiteCallIdentityTrust.warning,
    );
    expect(
      fixture.gateway.invocations.where(
        (entry) => entry.type == MatrixRtcInvocationType.securityState,
      ),
      hasLength(2),
    );
  });

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

  test('participant snapshots drive stable local spotlight state', () async {
    final fixture = _fixture();
    await fixture.coordinator.startGroupCall('!group:example.org');
    fixture.gateway.callParticipants = const <KiteCallParticipant>[
      KiteCallParticipant(
        participantId: 'alice-device',
        userId: '@alice:example.org',
        displayName: 'Alice',
        isLocal: false,
        isMicrophoneMuted: false,
        isCameraEnabled: true,
        isSpeaking: true,
      ),
      KiteCallParticipant(
        participantId: 'local-device',
        userId: '@me:example.org',
        displayName: 'Me',
        isLocal: true,
        isMicrophoneMuted: true,
        isCameraEnabled: true,
        isSpeaking: false,
      ),
    ];

    final participants = await fixture.coordinator.refreshParticipants();
    expect(
      participants.map((participant) => participant.participantId),
      <String>['alice-device', 'local-device'],
    );
    expect(
      () => participants.add(
        const KiteCallParticipant(
          participantId: 'extra',
          userId: '@extra:example.org',
          displayName: 'Extra',
          isLocal: false,
          isMicrophoneMuted: false,
          isCameraEnabled: false,
          isSpeaking: false,
        ),
      ),
      throwsUnsupportedError,
    );

    fixture.coordinator.spotlightParticipant('alice-device');
    expect(fixture.coordinator.spotlightParticipantId.value, 'alice-device');
    expect(
      () => fixture.coordinator.spotlightParticipant('missing-device'),
      throwsStateError,
    );

    fixture.gateway.callParticipants = const <KiteCallParticipant>[
      KiteCallParticipant(
        participantId: 'local-device',
        userId: '@me:example.org',
        displayName: 'Me',
        isLocal: true,
        isMicrophoneMuted: true,
        isCameraEnabled: true,
        isSpeaking: false,
      ),
    ];
    await fixture.coordinator.refreshParticipants();
    expect(fixture.coordinator.spotlightParticipantId.value, isNull);
    expect(
      fixture.gateway.invocations
          .where((entry) => entry.type == MatrixRtcInvocationType.participants)
          .map((entry) => entry.callId),
      <String?>['call-1', 'call-1'],
    );
  });

  test(
    'picture-in-picture records only platform-confirmed transitions',
    () async {
      final fixture = _fixture();
      await fixture.coordinator.startDirectVideoCall('!dm:example.org');

      expect(
        await fixture.coordinator.refreshPictureInPictureSupport(),
        isTrue,
      );
      await fixture.coordinator.enterPictureInPicture();
      await fixture.coordinator.enterPictureInPicture();
      expect(fixture.coordinator.isInPictureInPicture.value, isTrue);

      fixture.pictureInPicture.failNextWith = StateError('pip exit failed');
      await expectLater(
        fixture.coordinator.exitPictureInPicture(),
        throwsStateError,
      );
      expect(fixture.coordinator.isInPictureInPicture.value, isTrue);

      await fixture.coordinator.exitPictureInPicture();
      expect(fixture.coordinator.isInPictureInPicture.value, isFalse);
      expect(
        fixture.pictureInPicture.invocations.map((entry) => entry.type),
        <PictureInPictureInvocationType>[
          PictureInPictureInvocationType.support,
          PictureInPictureInvocationType.enter,
          PictureInPictureInvocationType.exit,
          PictureInPictureInvocationType.exit,
        ],
      );
    },
  );

  test('unsupported picture-in-picture never invokes platform entry', () async {
    final fixture = _fixture();
    fixture.pictureInPicture.supported = false;
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');

    expect(await fixture.coordinator.refreshPictureInPictureSupport(), isFalse);
    await expectLater(
      fixture.coordinator.enterPictureInPicture(),
      throwsStateError,
    );
    expect(fixture.coordinator.isInPictureInPicture.value, isFalse);
    expect(
      fixture.pictureInPicture.invocations.map((entry) => entry.type),
      <PictureInPictureInvocationType>[PictureInPictureInvocationType.support],
    );
  });

  test('stale microphone completion cannot mute a replacement call', () async {
    final fixture = _fixture(seed: 80);
    await fixture.coordinator.startDirectVoiceCall('!first:example.org');
    fixture.gateway.holdNextInvocation(
      MatrixRtcInvocationType.setMicrophoneMuted,
    );

    final pending = fixture.coordinator.setMicrophoneMuted(true);
    await Future<void>.delayed(Duration.zero);
    expect(
      fixture.gateway.hasHeldInvocation(
        MatrixRtcInvocationType.setMicrophoneMuted,
      ),
      isTrue,
    );

    await _replaceWithVideoCall(fixture, '!replacement:example.org');
    fixture.gateway.completeHeldInvocation(
      MatrixRtcInvocationType.setMicrophoneMuted,
    );
    await pending;

    expect(
      fixture.coordinator.session.value?.roomId,
      '!replacement:example.org',
    );
    expect(fixture.coordinator.isMicrophoneMuted.value, isFalse);
  });

  test(
    'stale camera completions cannot alter a replacement video call',
    () async {
      final fixture = _fixture(seed: 90);
      await fixture.coordinator.startDirectVideoCall('!first:example.org');
      fixture.gateway.holdNextInvocation(
        MatrixRtcInvocationType.setCameraEnabled,
      );

      final pendingDisable = fixture.coordinator.setCameraEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.gateway.hasHeldInvocation(
          MatrixRtcInvocationType.setCameraEnabled,
        ),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!second:example.org');
      fixture.gateway.completeHeldInvocation(
        MatrixRtcInvocationType.setCameraEnabled,
      );
      await pendingDisable;
      expect(fixture.coordinator.isCameraEnabled.value, isTrue);

      fixture.gateway.holdNextInvocation(MatrixRtcInvocationType.switchCamera);
      final pendingSwitch = fixture.coordinator.switchCamera();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.gateway.hasHeldInvocation(MatrixRtcInvocationType.switchCamera),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!third:example.org');
      fixture.gateway.completeHeldInvocation(
        MatrixRtcInvocationType.switchCamera,
      );
      await pendingSwitch;
      expect(fixture.coordinator.cameraFacing.value, KiteCameraFacing.front);
    },
  );

  test(
    'stale audio route refresh and selection cannot leak across calls',
    () async {
      final fixture = _fixture(seed: 100);
      await fixture.coordinator.startDirectVoiceCall('!first:example.org');
      fixture.gateway.audioRoutes = const <KiteAudioRoute>[
        KiteAudioRoute(
          id: 'wired',
          label: 'Wired headset',
          kind: KiteAudioRouteKind.wired,
        ),
      ];
      fixture.gateway.holdNextInvocation(
        MatrixRtcInvocationType.availableAudioRoutes,
      );

      final pendingRefresh = fixture.coordinator.refreshAudioRoutes();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.gateway.hasHeldInvocation(
          MatrixRtcInvocationType.availableAudioRoutes,
        ),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!second:example.org');
      fixture.gateway.completeHeldInvocation(
        MatrixRtcInvocationType.availableAudioRoutes,
      );
      final staleRoutes = await pendingRefresh;
      expect(staleRoutes.single.id, 'wired');
      expect(fixture.coordinator.audioRoutes.value, isEmpty);

      fixture.gateway.audioRoutes = const <KiteAudioRoute>[
        KiteAudioRoute(
          id: 'speaker',
          label: 'Speaker',
          kind: KiteAudioRouteKind.speaker,
        ),
      ];
      await fixture.coordinator.refreshAudioRoutes();
      fixture.gateway.holdNextInvocation(
        MatrixRtcInvocationType.selectAudioRoute,
      );
      final pendingSelection = fixture.coordinator.selectAudioRoute('speaker');
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.gateway.hasHeldInvocation(
          MatrixRtcInvocationType.selectAudioRoute,
        ),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!third:example.org');
      fixture.gateway.completeHeldInvocation(
        MatrixRtcInvocationType.selectAudioRoute,
      );
      await pendingSelection;
      expect(fixture.coordinator.selectedAudioRouteId.value, isNull);
    },
  );

  test(
    'stale participant snapshots cannot repopulate a replacement call',
    () async {
      final fixture = _fixture(seed: 110);
      await fixture.coordinator.startGroupCall('!first:example.org');
      fixture.gateway.callParticipants = const <KiteCallParticipant>[
        KiteCallParticipant(
          participantId: 'alice-device',
          userId: '@alice:example.org',
          displayName: 'Alice',
          isLocal: false,
          isMicrophoneMuted: false,
          isCameraEnabled: true,
          isSpeaking: true,
        ),
      ];
      fixture.gateway.holdNextInvocation(MatrixRtcInvocationType.participants);

      final pending = fixture.coordinator.refreshParticipants();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.gateway.hasHeldInvocation(MatrixRtcInvocationType.participants),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!replacement:example.org');
      fixture.gateway.completeHeldInvocation(
        MatrixRtcInvocationType.participants,
      );
      final staleParticipants = await pending;

      expect(staleParticipants.single.participantId, 'alice-device');
      expect(fixture.coordinator.participants.value, isEmpty);
      expect(fixture.coordinator.spotlightParticipantId.value, isNull);
    },
  );

  test(
    'stale picture-in-picture completions cannot alter a replacement call',
    () async {
      final fixture = _fixture(seed: 120);
      await fixture.coordinator.startDirectVideoCall('!first:example.org');
      fixture.pictureInPicture.holdNextInvocation(
        PictureInPictureInvocationType.support,
      );

      final pendingSupport = fixture.coordinator
          .refreshPictureInPictureSupport();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.pictureInPicture.hasHeldInvocation(
          PictureInPictureInvocationType.support,
        ),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!second:example.org');
      fixture.pictureInPicture.completeHeldInvocation(
        PictureInPictureInvocationType.support,
      );
      expect(await pendingSupport, isTrue);
      expect(fixture.coordinator.isPictureInPictureSupported.value, isFalse);

      expect(
        await fixture.coordinator.refreshPictureInPictureSupport(),
        isTrue,
      );
      fixture.pictureInPicture.holdNextInvocation(
        PictureInPictureInvocationType.enter,
      );
      final pendingEnter = fixture.coordinator.enterPictureInPicture();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.pictureInPicture.hasHeldInvocation(
          PictureInPictureInvocationType.enter,
        ),
        isTrue,
      );

      await _replaceWithVideoCall(fixture, '!third:example.org');
      fixture.pictureInPicture.completeHeldInvocation(
        PictureInPictureInvocationType.enter,
      );
      await pendingEnter;
      expect(fixture.coordinator.isInPictureInPicture.value, isFalse);
    },
  );

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

Future<void> _replaceWithVideoCall(_CallFixture fixture, String roomId) async {
  final current = fixture.coordinator.session.value;
  if (current == null) {
    throw StateError('Expected an active call before replacement.');
  }
  if (!fixture.coordinator.endCallFromSync(current.callId)) {
    throw StateError('Expected the current call to end from sync.');
  }
  fixture.coordinator.clearEndedCall();
  await fixture.coordinator.startDirectVideoCall(roomId);
}

_CallFixture _fixture({int seed = 0}) {
  final gateway = DeterministicMatrixRtcGateway(seed: seed);
  final pictureInPicture = DeterministicPictureInPicturePort();
  final logs = MemoryStructuredLogSink();
  final coordinator = KiteCallCoordinator(
    gateway: gateway,
    pictureInPicture: pictureInPicture,
    logger: StructuredLogger(
      sink: logs,
      traceIds: SequenceTraceIdGenerator(seed: 100),
    ),
  );
  return _CallFixture(
    gateway: gateway,
    pictureInPicture: pictureInPicture,
    logs: logs,
    coordinator: coordinator,
  );
}

final class _CallFixture {
  const _CallFixture({
    required this.gateway,
    required this.pictureInPicture,
    required this.logs,
    required this.coordinator,
  });

  final DeterministicMatrixRtcGateway gateway;
  final DeterministicPictureInPicturePort pictureInPicture;
  final MemoryStructuredLogSink logs;
  final KiteCallCoordinator coordinator;
}
