import 'package:kite/diagnostics/structured_logging.dart';
import 'package:signals/signals.dart';

enum KiteCallKind { voice, video }

enum KiteCallScope { direct, group }

enum KiteCallDirection { outgoing, incoming }

enum KiteCallPhase { idle, ringing, connecting, active, ended }

enum KiteCallEndReason { declined, hungUp }

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
  });

  Future<MatrixRtcSessionDescriptor> joinGroupCall({
    required String roomId,
    required String callId,
    required KiteCallKind kind,
  });

  Future<void> acceptCall(String callId);

  Future<void> declineCall(String callId);

  Future<void> hangUp(String callId);
}

final class KiteCallCoordinator {
  factory KiteCallCoordinator({
    required MatrixRtcGateway gateway,
    required StructuredLogger logger,
  }) {
    return KiteCallCoordinator._(gateway, logger);
  }

  KiteCallCoordinator._(this._gateway, this._logger);

  final MatrixRtcGateway _gateway;
  final StructuredLogger _logger;

  final Signal<KiteCallSession?> session = signal<KiteCallSession?>(null);
  final Signal<KiteCallPhase> phase = signal<KiteCallPhase>(KiteCallPhase.idle);
  final Signal<bool> isVideo = signal<bool>(false);
  final Signal<bool> isGroupCall = signal<bool>(false);

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
    session.value = KiteCallSession.fromDescriptor(
      descriptor,
      direction: KiteCallDirection.incoming,
    );
    isVideo.value = descriptor.kind == KiteCallKind.video;
    isGroupCall.value = descriptor.scope == KiteCallScope.group;
    phase.value = KiteCallPhase.ringing;
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
      trace.log(LogLevel.info, DiagnosticEvent.completed);
    } catch (_) {
      trace.log(LogLevel.error, DiagnosticEvent.failed);
      rethrow;
    }
  }

  Future<void> hangUp() async {
    final current = session.value;
    if (current == null ||
        (phase.value != KiteCallPhase.connecting &&
            phase.value != KiteCallPhase.active)) {
      throw StateError('No connecting or active call to hang up.');
    }

    final trace = _logger.trace(
      DiagnosticFlow.call,
      DiagnosticOperation.callSession,
    );
    trace.log(LogLevel.info, DiagnosticEvent.started);

    try {
      await _gateway.hangUp(current.callId);
      session.value = current.copyWith(endReason: KiteCallEndReason.hungUp);
      phase.value = KiteCallPhase.ended;
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
    phase.value = KiteCallPhase.idle;
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
    phase.value = KiteCallPhase.active;
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
    phase.value = KiteCallPhase.idle;
  }
}
