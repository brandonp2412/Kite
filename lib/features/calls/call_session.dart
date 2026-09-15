import 'package:kite/diagnostics/structured_logging.dart';
import 'package:signals/signals.dart';

enum KiteCallKind { voice, video }

enum KiteCallScope { direct, group }

enum MatrixRtcLaunchIntent {
  startCall,
  joinExisting,
  startCallVoice,
  joinExistingVoice,
  startCallDm,
  joinExistingDm,
  startCallDmVoice,
  joinExistingDmVoice,
}

extension MatrixRtcLaunchIntentValue on MatrixRtcLaunchIntent {
  String get elementCallValue => switch (this) {
    MatrixRtcLaunchIntent.startCall => 'start_call',
    MatrixRtcLaunchIntent.joinExisting => 'join_existing',
    MatrixRtcLaunchIntent.startCallVoice => 'start_call_voice',
    MatrixRtcLaunchIntent.joinExistingVoice => 'join_existing_voice',
    MatrixRtcLaunchIntent.startCallDm => 'start_call_dm',
    MatrixRtcLaunchIntent.joinExistingDm => 'join_existing_dm',
    MatrixRtcLaunchIntent.startCallDmVoice => 'start_call_dm_voice',
    MatrixRtcLaunchIntent.joinExistingDmVoice => 'join_existing_dm_voice',
  };
}

enum KiteCallDirection { outgoing, incoming }

enum KiteCallPhase { idle, ringing, connecting, active, reconnecting, ended }

enum KiteCallEndReason { declined, hungUp, missed, remoteEnded }

enum KiteCallIdentityTrust { unknown, trusted, warning }

final class KiteCallSecurityState {
  const KiteCallSecurityState({
    required this.e2eeEnabled,
    required this.identityTrust,
  });

  final bool e2eeEnabled;
  final KiteCallIdentityTrust identityTrust;

  bool get hasTrustWarning =>
      !e2eeEnabled || identityTrust == KiteCallIdentityTrust.warning;
}

enum KiteCallAppState { foreground, background, locked }

enum KiteCameraFacing { front, rear }

enum KiteAudioRouteKind {
  systemDefault,
  earpiece,
  speaker,
  bluetooth,
  wired,
  other,
}

final class KiteAudioRoute {
  const KiteAudioRoute({
    required this.id,
    required this.label,
    required this.kind,
  });

  final String id;
  final String label;
  final KiteAudioRouteKind kind;
}

final class KiteCallParticipant {
  const KiteCallParticipant({
    required this.participantId,
    required this.userId,
    required this.displayName,
    required this.isLocal,
    required this.isMicrophoneMuted,
    required this.isCameraEnabled,
    required this.isSpeaking,
    this.avatarUrl,
  });

  final String participantId;
  final String userId;
  final String displayName;
  final bool isLocal;
  final bool isMicrophoneMuted;
  final bool isCameraEnabled;
  final bool isSpeaking;
  final Uri? avatarUrl;
}

final class KiteCallContinuationCapabilities {
  const KiteCallContinuationCapabilities({
    required this.background,
    required this.locked,
  });

  static const none = KiteCallContinuationCapabilities(
    background: false,
    locked: false,
  );

  final bool background;
  final bool locked;

  bool supports(KiteCallAppState state) => switch (state) {
    KiteCallAppState.foreground => true,
    KiteCallAppState.background => background,
    KiteCallAppState.locked => locked,
  };
}

final class MatrixRtcLaunchConfig {
  const MatrixRtcLaunchConfig({
    required this.intent,
    required this.perParticipantE2ee,
    required this.controlledAudioDevices,
  });

  factory MatrixRtcLaunchConfig.start({
    required KiteCallKind kind,
    required KiteCallScope scope,
  }) {
    return MatrixRtcLaunchConfig(
      intent: switch ((scope, kind)) {
        (KiteCallScope.direct, KiteCallKind.video) =>
          MatrixRtcLaunchIntent.startCallDm,
        (KiteCallScope.direct, KiteCallKind.voice) =>
          MatrixRtcLaunchIntent.startCallDmVoice,
        (KiteCallScope.group, KiteCallKind.video) =>
          MatrixRtcLaunchIntent.startCall,
        (KiteCallScope.group, KiteCallKind.voice) =>
          MatrixRtcLaunchIntent.startCallVoice,
      },
      perParticipantE2ee: true,
      controlledAudioDevices: true,
    );
  }

  factory MatrixRtcLaunchConfig.join({
    required KiteCallKind kind,
    required KiteCallScope scope,
  }) {
    return MatrixRtcLaunchConfig(
      intent: switch ((scope, kind)) {
        (KiteCallScope.direct, KiteCallKind.video) =>
          MatrixRtcLaunchIntent.joinExistingDm,
        (KiteCallScope.direct, KiteCallKind.voice) =>
          MatrixRtcLaunchIntent.joinExistingDmVoice,
        (KiteCallScope.group, KiteCallKind.video) =>
          MatrixRtcLaunchIntent.joinExisting,
        (KiteCallScope.group, KiteCallKind.voice) =>
          MatrixRtcLaunchIntent.joinExistingVoice,
      },
      perParticipantE2ee: true,
      controlledAudioDevices: true,
    );
  }

  final MatrixRtcLaunchIntent intent;
  final bool perParticipantE2ee;
  final bool controlledAudioDevices;
}

final class MatrixRtcSessionDescriptor {
  const MatrixRtcSessionDescriptor({
    required this.callId,
    required this.roomId,
    required this.kind,
    required this.scope,
  });

  final String callId;
  final String roomId;
  final KiteCallKind kind;
  final KiteCallScope scope;
}

final class KiteCallActivity {
  const KiteCallActivity({
    required this.callId,
    required this.roomId,
    required this.kind,
    required this.scope,
    required this.direction,
    required this.phase,
    this.endReason,
  });

  factory KiteCallActivity.fromSession(
    KiteCallSession session,
    KiteCallPhase phase,
  ) {
    return KiteCallActivity(
      callId: session.callId,
      roomId: session.roomId,
      kind: session.kind,
      scope: session.scope,
      direction: session.direction,
      phase: phase,
      endReason: session.endReason,
    );
  }

  final String callId;
  final String roomId;
  final KiteCallKind kind;
  final KiteCallScope scope;
  final KiteCallDirection direction;
  final KiteCallPhase phase;
  final KiteCallEndReason? endReason;

  bool get isActive => switch (phase) {
    KiteCallPhase.ringing ||
    KiteCallPhase.connecting ||
    KiteCallPhase.active ||
    KiteCallPhase.reconnecting => true,
    KiteCallPhase.idle || KiteCallPhase.ended => false,
  };
}

final class KiteCallSession {
  const KiteCallSession({
    required this.callId,
    required this.roomId,
    required this.kind,
    required this.scope,
    required this.direction,
    this.endReason,
  });

  factory KiteCallSession.fromDescriptor(
    MatrixRtcSessionDescriptor descriptor, {
    required KiteCallDirection direction,
    KiteCallEndReason? endReason,
  }) {
    return KiteCallSession(
      callId: descriptor.callId,
      roomId: descriptor.roomId,
      kind: descriptor.kind,
      scope: descriptor.scope,
      direction: direction,
      endReason: endReason,
    );
  }

  final String callId;
  final String roomId;
  final KiteCallKind kind;
  final KiteCallScope scope;
  final KiteCallDirection direction;
  final KiteCallEndReason? endReason;

  KiteCallSession copyWith({KiteCallEndReason? endReason}) {
    return KiteCallSession(
      callId: callId,
      roomId: roomId,
      kind: kind,
      scope: scope,
      direction: direction,
      endReason: endReason ?? this.endReason,
    );
  }
}

abstract interface class MatrixRtcGateway {
  Future<MatrixRtcSessionDescriptor> startCall({
    required String roomId,
    required KiteCallKind kind,
    required KiteCallScope scope,
    required MatrixRtcLaunchConfig launchConfig,
  });

  Future<MatrixRtcSessionDescriptor> joinGroupCall({
    required String roomId,
    required String callId,
    required KiteCallKind kind,
    required MatrixRtcLaunchConfig launchConfig,
  });

  Future<void> acceptCall(String callId);

  Future<void> declineCall(String callId);

  Future<void> hangUp(String callId);

  Future<void> setMicrophoneMuted({
    required String callId,
    required bool muted,
  });

  Future<void> setCameraEnabled({
    required String callId,
    required bool enabled,
  });

  Future<KiteCameraFacing> switchCamera(String callId);

  Future<List<KiteAudioRoute>> availableAudioRoutes(String callId);

  Future<void> selectAudioRoute({
    required String callId,
    required String routeId,
  });

  Future<void> setMediaInterrupted({
    required String callId,
    required bool interrupted,
  });

  Future<KiteCallContinuationCapabilities> continuationCapabilities(
    String callId,
  );

  Future<void> setAppState({
    required String callId,
    required KiteCallAppState state,
  });

  Future<void> reconnect(String callId);

  Future<KiteCallSecurityState> securityState(String callId);

  Future<List<KiteCallParticipant>> participants(String callId);
}

abstract interface class CallPictureInPicturePort {
  Future<bool> isSupported();

  Future<void> enter(String callId);

  Future<void> exit(String callId);
}

final class KiteCallCoordinator {
  factory KiteCallCoordinator({
    required MatrixRtcGateway gateway,
    required CallPictureInPicturePort pictureInPicture,
    required StructuredLogger logger,
  }) {
    return KiteCallCoordinator._(gateway, pictureInPicture, logger);
  }

  KiteCallCoordinator._(this._gateway, this._pictureInPicture, this._logger);

  final MatrixRtcGateway _gateway;
  final CallPictureInPicturePort _pictureInPicture;
  final StructuredLogger _logger;

  final Signal<KiteCallSession?> session = signal<KiteCallSession?>(null);
  final Signal<KiteCallPhase> phase = signal<KiteCallPhase>(KiteCallPhase.idle);
  final Signal<bool> isVideo = signal<bool>(false);
  final Signal<bool> isGroupCall = signal<bool>(false);
  final Signal<bool> isMicrophoneMuted = signal<bool>(false);
  final Signal<bool> isCameraEnabled = signal<bool>(false);
  final Signal<KiteCameraFacing> cameraFacing = signal<KiteCameraFacing>(
    KiteCameraFacing.front,
  );
  final Signal<List<KiteAudioRoute>> audioRoutes = signal<List<KiteAudioRoute>>(
    const <KiteAudioRoute>[],
  );
  final Signal<String?> selectedAudioRouteId = signal<String?>(null);
  final Signal<bool> isMediaInterrupted = signal<bool>(false);
  final Signal<KiteCallContinuationCapabilities> continuationCapabilities =
      signal<KiteCallContinuationCapabilities>(
        KiteCallContinuationCapabilities.none,
      );
  final Signal<KiteCallAppState> appState = signal<KiteCallAppState>(
    KiteCallAppState.foreground,
  );
  final Signal<KiteCallActivity?> activity = signal<KiteCallActivity?>(null);
  final Signal<KiteCallSecurityState?> securityState =
      signal<KiteCallSecurityState?>(null);
  final Signal<List<KiteCallParticipant>> participants =
      signal<List<KiteCallParticipant>>(const <KiteCallParticipant>[]);
  final Signal<String?> spotlightParticipantId = signal<String?>(null);
  final Signal<bool> isPictureInPictureSupported = signal<bool>(false);
  final Signal<bool> isInPictureInPicture = signal<bool>(false);

  Future<void> startDirectVoiceCall(String roomId) {
    return _startOutgoing(
      roomId: roomId,
      kind: KiteCallKind.voice,
      scope: KiteCallScope.direct,
    );
  }

  Future<void> startDirectVideoCall(String roomId) {
    return _startOutgoing(
      roomId: roomId,
      kind: KiteCallKind.video,
      scope: KiteCallScope.direct,
    );
  }

  Future<void> startGroupCall(
    String roomId, {
    KiteCallKind kind = KiteCallKind.video,
  }) {
    return _startOutgoing(
      roomId: roomId,
      kind: kind,
      scope: KiteCallScope.group,
    );
  }

  Future<void> joinGroupCall({
    required String roomId,
    required String callId,
    KiteCallKind kind = KiteCallKind.video,
  }) async {
    _ensureAvailable();
    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);
    _prepareConnecting(kind: kind, scope: KiteCallScope.group);

    try {
      final descriptor = await _gateway.joinGroupCall(
        roomId: roomId,
        callId: callId,
        kind: kind,
        launchConfig: MatrixRtcLaunchConfig.join(
          kind: kind,
          scope: KiteCallScope.group,
        ),
      );
      _setConnectedSession(descriptor, direction: KiteCallDirection.outgoing);
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      _resetAfterFailure();
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  void registerIncomingCall(MatrixRtcSessionDescriptor descriptor) {
    _ensureAvailable();
    _resetCallControls();
    session.value = KiteCallSession.fromDescriptor(
      descriptor,
      direction: KiteCallDirection.incoming,
    );
    isVideo.value = descriptor.kind == KiteCallKind.video;
    isGroupCall.value = descriptor.scope == KiteCallScope.group;
    phase.value = KiteCallPhase.ringing;
    _publishActivity();
  }

  Future<void> acceptIncomingCall() async {
    final current = _requireIncomingRingingSession();
    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);
    phase.value = KiteCallPhase.connecting;

    try {
      await _gateway.acceptCall(current.callId);
      phase.value = KiteCallPhase.active;
      _publishActivity();
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      phase.value = KiteCallPhase.ringing;
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  Future<void> declineIncomingCall() async {
    final current = _requireIncomingRingingSession();
    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);

    try {
      await _gateway.declineCall(current.callId);
      session.value = current.copyWith(endReason: KiteCallEndReason.declined);
      phase.value = KiteCallPhase.ended;
      _publishActivity();
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  bool endIncomingCallFromSync(String callId) {
    final current = session.value;
    if (current == null ||
        current.direction != KiteCallDirection.incoming ||
        phase.value != KiteCallPhase.ringing ||
        current.callId != callId) {
      return false;
    }
    return endCallFromSync(callId);
  }

  bool endCallFromSync(String callId) {
    final current = session.value;
    final currentPhase = phase.value;
    if (current == null ||
        current.callId != callId ||
        currentPhase == KiteCallPhase.idle ||
        currentPhase == KiteCallPhase.ended) {
      return false;
    }

    final reason =
        current.direction == KiteCallDirection.incoming &&
            currentPhase == KiteCallPhase.ringing
        ? KiteCallEndReason.missed
        : KiteCallEndReason.remoteEnded;
    session.value = current.copyWith(endReason: reason);
    isInPictureInPicture.value = false;
    phase.value = KiteCallPhase.ended;
    _publishActivity();
    return true;
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    final current = _requireActiveSession();
    if (isMicrophoneMuted.value == muted) return;

    await _gateway.setMicrophoneMuted(callId: current.callId, muted: muted);
    if (!_isCurrentCall(current.callId)) return;
    isMicrophoneMuted.value = muted;
  }

  Future<void> setCameraEnabled(bool enabled) async {
    final current = _requireActiveVideoSession();
    if (isCameraEnabled.value == enabled) return;

    await _gateway.setCameraEnabled(callId: current.callId, enabled: enabled);
    if (!_isCurrentCall(current.callId)) return;
    isCameraEnabled.value = enabled;
  }

  Future<void> switchCamera() async {
    final current = _requireActiveVideoSession();
    if (!isCameraEnabled.value) {
      throw StateError('Camera must be enabled before switching cameras.');
    }

    final facing = await _gateway.switchCamera(current.callId);
    if (!_isCurrentCall(current.callId)) return;
    cameraFacing.value = facing;
  }

  Future<List<KiteAudioRoute>> refreshAudioRoutes() async {
    final current = _requireActiveSession();
    final routes = List<KiteAudioRoute>.unmodifiable(
      await _gateway.availableAudioRoutes(current.callId),
    );
    if (!_isCurrentCall(current.callId)) return routes;
    audioRoutes.value = routes;
    if (selectedAudioRouteId.value != null &&
        !routes.any((route) => route.id == selectedAudioRouteId.value)) {
      selectedAudioRouteId.value = null;
    }
    return routes;
  }

  Future<void> selectAudioRoute(String routeId) async {
    final current = _requireActiveSession();
    final knownRoute = audioRoutes.value.any((route) => route.id == routeId);
    if (!knownRoute) {
      throw StateError('Audio route is not available for this call.');
    }
    if (selectedAudioRouteId.value == routeId) return;

    await _gateway.selectAudioRoute(callId: current.callId, routeId: routeId);
    if (!_isCurrentCall(current.callId)) return;
    selectedAudioRouteId.value = routeId;
  }

  Future<void> setMediaInterrupted(bool interrupted) async {
    final current = _requireReconnectableSession();
    if (isMediaInterrupted.value == interrupted) return;

    await _gateway.setMediaInterrupted(
      callId: current.callId,
      interrupted: interrupted,
    );
    if (!_isCurrentCall(current.callId)) return;
    isMediaInterrupted.value = interrupted;
  }

  Future<KiteCallContinuationCapabilities>
  refreshContinuationCapabilities() async {
    final current = _requireReconnectableSession();
    final capabilities = await _gateway.continuationCapabilities(
      current.callId,
    );
    continuationCapabilities.value = capabilities;
    return capabilities;
  }

  Future<void> setAppState(KiteCallAppState state) async {
    final current = _requireReconnectableSession();
    if (appState.value == state) return;
    if (!continuationCapabilities.value.supports(state)) {
      throw StateError('The current platform cannot continue this call there.');
    }

    await _gateway.setAppState(callId: current.callId, state: state);
    if (!_isCurrentCall(current.callId)) return;
    appState.value = state;
  }

  void markTransientNetworkLoss() {
    _requireActiveSession();
    phase.value = KiteCallPhase.reconnecting;
    _publishActivity();
  }

  Future<void> reconnectAfterTransientNetworkLoss() async {
    final current = _requireReconnectableSession();
    if (phase.value != KiteCallPhase.reconnecting) {
      phase.value = KiteCallPhase.reconnecting;
      _publishActivity();
    }

    try {
      await _gateway.reconnect(current.callId);
      if (!_isCurrentCall(current.callId)) return;
      phase.value = KiteCallPhase.active;
      _publishActivity();
    } catch (_) {
      if (_isCurrentCall(current.callId)) {
        phase.value = KiteCallPhase.reconnecting;
        _publishActivity();
      }
      rethrow;
    }
  }

  Future<KiteCallSecurityState> refreshSecurityState() async {
    final current = _requireActiveSession();
    final state = await _gateway.securityState(current.callId);
    securityState.value = state;
    return state;
  }

  Future<List<KiteCallParticipant>> refreshParticipants() async {
    final current = _requireActiveSession();
    final nextParticipants = List<KiteCallParticipant>.unmodifiable(
      await _gateway.participants(current.callId),
    );
    if (!_isCurrentCall(current.callId)) return nextParticipants;
    participants.value = nextParticipants;
    final spotlight = spotlightParticipantId.value;
    if (spotlight != null &&
        !nextParticipants.any(
          (participant) => participant.participantId == spotlight,
        )) {
      spotlightParticipantId.value = null;
    }
    return nextParticipants;
  }

  void spotlightParticipant(String? participantId) {
    _requireActiveSession();
    if (participantId != null &&
        !participants.value.any(
          (participant) => participant.participantId == participantId,
        )) {
      throw StateError('Participant is not present in the current call.');
    }
    spotlightParticipantId.value = participantId;
  }

  Future<bool> refreshPictureInPictureSupport() async {
    final current = _requireActiveSession();
    final supported = await _pictureInPicture.isSupported();
    if (!_isCurrentCall(current.callId)) return supported;
    isPictureInPictureSupported.value = supported;
    if (!supported) {
      isInPictureInPicture.value = false;
    }
    return supported;
  }

  Future<void> enterPictureInPicture() async {
    final current = _requireActiveSession();
    if (!isPictureInPictureSupported.value) {
      throw StateError('Picture-in-picture is not supported on this platform.');
    }
    if (isInPictureInPicture.value) return;

    await _pictureInPicture.enter(current.callId);
    if (!_isCurrentCall(current.callId)) return;
    isInPictureInPicture.value = true;
  }

  Future<void> exitPictureInPicture() async {
    final current = _requireActiveSession();
    if (!isInPictureInPicture.value) return;

    await _pictureInPicture.exit(current.callId);
    if (!_isCurrentCall(current.callId)) return;
    isInPictureInPicture.value = false;
  }

  Future<void> hangUp() async {
    final current = session.value;
    if (current == null ||
        (phase.value != KiteCallPhase.connecting &&
            phase.value != KiteCallPhase.active &&
            phase.value != KiteCallPhase.reconnecting)) {
      throw StateError(
        'No connecting, active, or reconnecting call to hang up.',
      );
    }

    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);

    try {
      await _gateway.hangUp(current.callId);
      session.value = current.copyWith(endReason: KiteCallEndReason.hungUp);
      isInPictureInPicture.value = false;
      phase.value = KiteCallPhase.ended;
      _publishActivity();
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  void clearEndedCall() {
    if (phase.value != KiteCallPhase.ended) {
      throw StateError('Only an ended call can be cleared.');
    }
    session.value = null;
    isVideo.value = false;
    isGroupCall.value = false;
    _resetCallControls();
    phase.value = KiteCallPhase.idle;
    activity.value = null;
  }

  Future<void> _startOutgoing({
    required String roomId,
    required KiteCallKind kind,
    required KiteCallScope scope,
  }) async {
    _ensureAvailable();
    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);
    _prepareConnecting(kind: kind, scope: scope);

    try {
      final descriptor = await _gateway.startCall(
        roomId: roomId,
        kind: kind,
        scope: scope,
        launchConfig: MatrixRtcLaunchConfig.start(kind: kind, scope: scope),
      );
      _setConnectedSession(descriptor, direction: KiteCallDirection.outgoing);
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      _resetAfterFailure();
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  void _prepareConnecting({
    required KiteCallKind kind,
    required KiteCallScope scope,
  }) {
    session.value = null;
    isVideo.value = kind == KiteCallKind.video;
    isGroupCall.value = scope == KiteCallScope.group;
    _resetCallControls();
    phase.value = KiteCallPhase.connecting;
  }

  void _setConnectedSession(
    MatrixRtcSessionDescriptor descriptor, {
    required KiteCallDirection direction,
  }) {
    session.value = KiteCallSession.fromDescriptor(
      descriptor,
      direction: direction,
    );
    isVideo.value = descriptor.kind == KiteCallKind.video;
    isGroupCall.value = descriptor.scope == KiteCallScope.group;
    isCameraEnabled.value = descriptor.kind == KiteCallKind.video;
    phase.value = KiteCallPhase.active;
    _publishActivity();
  }

  KiteCallSession _requireActiveSession() {
    final current = session.value;
    if (current == null || phase.value != KiteCallPhase.active) {
      throw StateError('No active call is available.');
    }
    return current;
  }

  KiteCallSession _requireReconnectableSession() {
    final current = session.value;
    if (current == null ||
        (phase.value != KiteCallPhase.active &&
            phase.value != KiteCallPhase.reconnecting)) {
      throw StateError('No active or reconnecting call is available.');
    }
    return current;
  }

  KiteCallSession _requireActiveVideoSession() {
    final current = _requireActiveSession();
    if (current.kind != KiteCallKind.video) {
      throw StateError('Camera controls require an active video call.');
    }
    return current;
  }

  KiteCallSession _requireIncomingRingingSession() {
    final current = session.value;
    if (current == null ||
        current.direction != KiteCallDirection.incoming ||
        phase.value != KiteCallPhase.ringing) {
      throw StateError('No incoming ringing call is available.');
    }
    return current;
  }

  void _ensureAvailable() {
    if (phase.value != KiteCallPhase.idle &&
        phase.value != KiteCallPhase.ended) {
      throw StateError('A call is already in progress.');
    }
  }

  void _resetAfterFailure() {
    session.value = null;
    isVideo.value = false;
    isGroupCall.value = false;
    _resetCallControls();
    phase.value = KiteCallPhase.idle;
    activity.value = null;
  }

  bool _isCurrentCall(String callId) => session.value?.callId == callId;

  void _publishActivity() {
    final current = session.value;
    activity.value = current == null
        ? null
        : KiteCallActivity.fromSession(current, phase.value);
  }

  void _resetCallControls() {
    isMicrophoneMuted.value = false;
    isCameraEnabled.value = false;
    cameraFacing.value = KiteCameraFacing.front;
    audioRoutes.value = const <KiteAudioRoute>[];
    selectedAudioRouteId.value = null;
    isMediaInterrupted.value = false;
    continuationCapabilities.value = KiteCallContinuationCapabilities.none;
    appState.value = KiteCallAppState.foreground;
    securityState.value = null;
    participants.value = const <KiteCallParticipant>[];
    spotlightParticipantId.value = null;
    isPictureInPictureSupported.value = false;
    isInPictureInPicture.value = false;
  }
}
