import 'dart:async';

import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/calls/matrix_call_deep_link.dart';

enum MatrixRtcInvocationType {
  start,
  joinGroup,
  accept,
  decline,
  hangUp,
  setMicrophoneMuted,
  setCameraEnabled,
  switchCamera,
  availableAudioRoutes,
  selectAudioRoute,
  setMediaInterrupted,
  continuationCapabilities,
  setAppState,
  reconnect,
  securityState,
  participants,
}

final class MatrixRtcInvocation {
  const MatrixRtcInvocation({
    required this.type,
    this.roomId,
    this.callId,
    this.kind,
    this.scope,
    this.enabled,
    this.routeId,
    this.appState,
    this.launchConfig,
  });

  final MatrixRtcInvocationType type;
  final String? roomId;
  final String? callId;
  final KiteCallKind? kind;
  final KiteCallScope? scope;
  final bool? enabled;
  final String? routeId;
  final KiteCallAppState? appState;
  final MatrixRtcLaunchConfig? launchConfig;
}

final class MatrixCallDeepLinkResolution {
  const MatrixCallDeepLinkResolution({
    required this.accountId,
    required this.roomIdOrAlias,
  });

  final String accountId;
  final String roomIdOrAlias;
}

final class DeterministicMatrixCallDeepLinkResolver
    implements MatrixCallDeepLinkResolverPort {
  MatrixRtcSessionDescriptor? descriptor;
  Object? failNextWith;
  final List<MatrixCallDeepLinkResolution> resolutions =
      <MatrixCallDeepLinkResolution>[];

  @override
  Future<MatrixRtcSessionDescriptor?> resolveActiveCall({
    required String accountId,
    required String roomIdOrAlias,
  }) async {
    resolutions.add(
      MatrixCallDeepLinkResolution(
        accountId: accountId,
        roomIdOrAlias: roomIdOrAlias,
      ),
    );
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    return descriptor;
  }
}

final class DeterministicMatrixRtcGateway implements MatrixRtcGateway {
  DeterministicMatrixRtcGateway({this.seed = 0});

  final int seed;
  final List<MatrixRtcInvocation> invocations = <MatrixRtcInvocation>[];
  int _counter = 0;
  Completer<MatrixRtcSessionDescriptor>? _heldStart;
  MatrixRtcSessionDescriptor? _heldStartDescriptor;
  Object? failNextWith;
  bool holdNextStart = false;
  KiteCameraFacing cameraFacing = KiteCameraFacing.front;
  KiteCallContinuationCapabilities callContinuationCapabilities =
      const KiteCallContinuationCapabilities(background: true, locked: true);
  List<KiteAudioRoute> audioRoutes = const <KiteAudioRoute>[
    KiteAudioRoute(
      id: 'system',
      label: 'System default',
      kind: KiteAudioRouteKind.systemDefault,
    ),
    KiteAudioRoute(
      id: 'speaker',
      label: 'Speaker',
      kind: KiteAudioRouteKind.speaker,
    ),
  ];
  KiteCallSecurityState callSecurityState = const KiteCallSecurityState(
    e2eeEnabled: true,
    identityTrust: KiteCallIdentityTrust.trusted,
  );
  List<KiteCallParticipant> callParticipants = const <KiteCallParticipant>[];

  @override
  Future<MatrixRtcSessionDescriptor> startCall({
    required String roomId,
    required KiteCallKind kind,
    required KiteCallScope scope,
    required MatrixRtcLaunchConfig launchConfig,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.start,
        roomId: roomId,
        kind: kind,
        scope: scope,
        launchConfig: launchConfig,
      ),
    );
    _throwIfRequested();
    _counter += 1;
    final descriptor = MatrixRtcSessionDescriptor(
      callId: 'call-${seed + _counter}',
      roomId: roomId,
      kind: kind,
      scope: scope,
    );
    if (!holdNextStart) return descriptor;

    holdNextStart = false;
    final completer = Completer<MatrixRtcSessionDescriptor>();
    _heldStart = completer;
    _heldStartDescriptor = descriptor;
    return completer.future;
  }

  @override
  Future<MatrixRtcSessionDescriptor> joinGroupCall({
    required String roomId,
    required String callId,
    required KiteCallKind kind,
    required MatrixRtcLaunchConfig launchConfig,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.joinGroup,
        roomId: roomId,
        callId: callId,
        kind: kind,
        scope: KiteCallScope.group,
        launchConfig: launchConfig,
      ),
    );
    _throwIfRequested();
    return MatrixRtcSessionDescriptor(
      callId: callId,
      roomId: roomId,
      kind: kind,
      scope: KiteCallScope.group,
    );
  }

  @override
  Future<void> acceptCall(String callId) async {
    invocations.add(
      MatrixRtcInvocation(type: MatrixRtcInvocationType.accept, callId: callId),
    );
    _throwIfRequested();
  }

  @override
  Future<void> declineCall(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.decline,
        callId: callId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> hangUp(String callId) async {
    invocations.add(
      MatrixRtcInvocation(type: MatrixRtcInvocationType.hangUp, callId: callId),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setMicrophoneMuted({
    required String callId,
    required bool muted,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.setMicrophoneMuted,
        callId: callId,
        enabled: muted,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setCameraEnabled({
    required String callId,
    required bool enabled,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.setCameraEnabled,
        callId: callId,
        enabled: enabled,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<KiteCameraFacing> switchCamera(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.switchCamera,
        callId: callId,
      ),
    );
    _throwIfRequested();
    cameraFacing = switch (cameraFacing) {
      KiteCameraFacing.front => KiteCameraFacing.rear,
      KiteCameraFacing.rear => KiteCameraFacing.front,
    };
    return cameraFacing;
  }

  @override
  Future<List<KiteAudioRoute>> availableAudioRoutes(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.availableAudioRoutes,
        callId: callId,
      ),
    );
    _throwIfRequested();
    return List<KiteAudioRoute>.unmodifiable(audioRoutes);
  }

  @override
  Future<void> selectAudioRoute({
    required String callId,
    required String routeId,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.selectAudioRoute,
        callId: callId,
        routeId: routeId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> setMediaInterrupted({
    required String callId,
    required bool interrupted,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.setMediaInterrupted,
        callId: callId,
        enabled: interrupted,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<KiteCallContinuationCapabilities> continuationCapabilities(
    String callId,
  ) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.continuationCapabilities,
        callId: callId,
      ),
    );
    _throwIfRequested();
    return callContinuationCapabilities;
  }

  @override
  Future<void> setAppState({
    required String callId,
    required KiteCallAppState state,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.setAppState,
        callId: callId,
        appState: state,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> reconnect(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.reconnect,
        callId: callId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<KiteCallSecurityState> securityState(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.securityState,
        callId: callId,
      ),
    );
    _throwIfRequested();
    return callSecurityState;
  }

  @override
  Future<List<KiteCallParticipant>> participants(String callId) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.participants,
        callId: callId,
      ),
    );
    _throwIfRequested();
    return List<KiteCallParticipant>.unmodifiable(callParticipants);
  }

  bool get hasHeldStart => _heldStart != null;

  void completeHeldStart() {
    final completer = _heldStart;
    final descriptor = _heldStartDescriptor;
    if (completer == null || descriptor == null) {
      throw StateError('No held call start is available.');
    }
    _heldStart = null;
    _heldStartDescriptor = null;
    completer.complete(descriptor);
  }

  void _throwIfRequested() {
    final error = failNextWith;
    failNextWith = null;
    if (error != null) throw error;
  }
}

enum PictureInPictureInvocationType { support, enter, exit }

final class PictureInPictureInvocation {
  const PictureInPictureInvocation({required this.type, this.callId});

  final PictureInPictureInvocationType type;
  final String? callId;
}

final class DeterministicPictureInPicturePort
    implements CallPictureInPicturePort {
  bool supported = true;
  Object? failNextWith;
  final List<PictureInPictureInvocation> invocations =
      <PictureInPictureInvocation>[];

  @override
  Future<bool> isSupported() async {
    invocations.add(
      const PictureInPictureInvocation(
        type: PictureInPictureInvocationType.support,
      ),
    );
    _throwIfRequested();
    return supported;
  }

  @override
  Future<void> enter(String callId) async {
    invocations.add(
      PictureInPictureInvocation(
        type: PictureInPictureInvocationType.enter,
        callId: callId,
      ),
    );
    _throwIfRequested();
  }

  @override
  Future<void> exit(String callId) async {
    invocations.add(
      PictureInPictureInvocation(
        type: PictureInPictureInvocationType.exit,
        callId: callId,
      ),
    );
    _throwIfRequested();
  }

  void _throwIfRequested() {
    final error = failNextWith;
    failNextWith = null;
    if (error != null) throw error;
  }
}
