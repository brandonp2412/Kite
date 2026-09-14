import 'dart:async';

import 'package:kite/features/calls/call_session.dart';

enum MatrixRtcInvocationType { start, joinGroup, accept, decline, hangUp }

final class MatrixRtcInvocation {
  const MatrixRtcInvocation({
    required this.type,
    this.roomId,
    this.callId,
    this.kind,
    this.scope,
  });

  final MatrixRtcInvocationType type;
  final String? roomId;
  final String? callId;
  final KiteCallKind? kind;
  final KiteCallScope? scope;
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

  @override
  Future<MatrixRtcSessionDescriptor> startCall({
    required String roomId,
    required KiteCallKind kind,
    required KiteCallScope scope,
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.start,
        roomId: roomId,
        kind: kind,
        scope: scope,
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
  }) async {
    invocations.add(
      MatrixRtcInvocation(
        type: MatrixRtcInvocationType.joinGroup,
        roomId: roomId,
        callId: callId,
        kind: kind,
        scope: KiteCallScope.group,
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
