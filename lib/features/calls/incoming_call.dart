import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';

enum IncomingCallNotificationResult {
  ignored,
  unavailable,
  busy,
  alreadyRinging,
  ringing;

  bool get admitsIncomingCallSurface => switch (this) {
    IncomingCallNotificationResult.alreadyRinging ||
    IncomingCallNotificationResult.ringing => true,
    IncomingCallNotificationResult.ignored ||
    IncomingCallNotificationResult.unavailable ||
    IncomingCallNotificationResult.busy => false,
  };
}

abstract interface class IncomingCallResolverPort {
  Future<MatrixRtcSessionDescriptor?> resolve({
    required String accountId,
    required String roomId,
    required String callId,
  });
}

abstract interface class IncomingCallRingtonePort {
  Future<void> start(String callId);

  Future<void> stop(String callId);
}

typedef IncomingCallRingtoneErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

final class IncomingCallCoordinator {
  factory IncomingCallCoordinator({
    required KiteCallCoordinator calls,
    required IncomingCallResolverPort resolver,
    required IncomingCallRingtonePort ringtone,
    IncomingCallRingtoneErrorHandler? onRingtoneError,
  }) => IncomingCallCoordinator._(calls, resolver, ringtone, onRingtoneError);

  const IncomingCallCoordinator._(
    this._calls,
    this._resolver,
    this._ringtone,
    this._onRingtoneError,
  );

  final KiteCallCoordinator _calls;
  final IncomingCallResolverPort _resolver;
  final IncomingCallRingtonePort _ringtone;
  final IncomingCallRingtoneErrorHandler? _onRingtoneError;

  Future<bool> admitNotification(KiteNotification notification) async {
    return (await handleNotification(notification)).admitsIncomingCallSurface;
  }

  Future<IncomingCallNotificationResult> handleNotification(
    KiteNotification notification,
  ) async {
    if (notification.kind != KiteNotificationKind.call) {
      return IncomingCallNotificationResult.ignored;
    }

    final destination = notification.destination;
    if (destination.kind != AppDestinationKind.call ||
        destination.callId == null) {
      throw StateError('Call notifications require an exact call destination.');
    }

    final callId = destination.callId!;
    final current = _calls.session.value;
    final phase = _calls.phase.value;
    if (current != null && phase == KiteCallPhase.ringing) {
      if (current.callId == callId && current.roomId == destination.roomId) {
        return IncomingCallNotificationResult.alreadyRinging;
      }
      return IncomingCallNotificationResult.busy;
    }
    if (phase != KiteCallPhase.idle && phase != KiteCallPhase.ended) {
      return IncomingCallNotificationResult.busy;
    }

    final descriptor = await _resolver.resolve(
      accountId: destination.accountId,
      roomId: destination.roomId,
      callId: callId,
    );
    if (descriptor == null) {
      return IncomingCallNotificationResult.unavailable;
    }
    if (descriptor.callId != callId ||
        descriptor.roomId != destination.roomId) {
      throw StateError(
        'Resolved MatrixRTC identity does not match the notification target.',
      );
    }

    _calls.registerIncomingCall(descriptor);
    await _startRingtone(callId);
    return IncomingCallNotificationResult.ringing;
  }

  Future<void> accept() async {
    final callId = _ringingCallId();
    await _calls.acceptIncomingCall();
    await _stopRingtone(callId);
  }

  Future<void> decline() async {
    final callId = _ringingCallId();
    await _calls.declineIncomingCall();
    await _stopRingtone(callId);
  }

  Future<bool> endFromSync(String callId) async {
    final current = _calls.session.value;
    final wasRinging =
        current?.callId == callId &&
        _calls.phase.value == KiteCallPhase.ringing;
    if (!_calls.endCallFromSync(callId)) return false;
    if (wasRinging) await _stopRingtone(callId);
    return true;
  }

  String _ringingCallId() {
    final current = _calls.session.value;
    if (current == null || _calls.phase.value != KiteCallPhase.ringing) {
      throw StateError('No incoming ringing call is available.');
    }
    return current.callId;
  }

  Future<void> _startRingtone(String callId) async {
    try {
      await _ringtone.start(callId);
    } catch (error, stackTrace) {
      _onRingtoneError?.call(error, stackTrace);
    }
  }

  Future<void> _stopRingtone(String callId) async {
    try {
      await _ringtone.stop(callId);
    } catch (error, stackTrace) {
      _onRingtoneError?.call(error, stackTrace);
    }
  }
}
