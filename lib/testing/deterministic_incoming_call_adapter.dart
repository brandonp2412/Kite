import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/calls/incoming_call.dart';

final class IncomingCallResolution {
  const IncomingCallResolution({
    required this.accountId,
    required this.roomId,
    required this.callId,
  });

  final String accountId;
  final String roomId;
  final String callId;
}

final class DeterministicIncomingCallResolver
    implements IncomingCallResolverPort {
  MatrixRtcSessionDescriptor? descriptor;
  Object? failNextWith;
  final List<IncomingCallResolution> resolutions = <IncomingCallResolution>[];

  @override
  Future<MatrixRtcSessionDescriptor?> resolve({
    required String accountId,
    required String roomId,
    required String callId,
  }) async {
    resolutions.add(
      IncomingCallResolution(
        accountId: accountId,
        roomId: roomId,
        callId: callId,
      ),
    );
    final failure = failNextWith;
    failNextWith = null;
    if (failure != null) throw failure;
    return descriptor;
  }
}

final class DeterministicIncomingCallRingtone
    implements IncomingCallRingtonePort {
  final List<String> startedCallIds = <String>[];
  final List<String> stoppedCallIds = <String>[];
  Object? failNextStartWith;
  Object? failNextStopWith;

  @override
  Future<void> start(String callId) async {
    final failure = failNextStartWith;
    failNextStartWith = null;
    if (failure != null) throw failure;
    startedCallIds.add(callId);
  }

  @override
  Future<void> stop(String callId) async {
    final failure = failNextStopWith;
    failNextStopWith = null;
    if (failure != null) throw failure;
    stoppedCallIds.add(callId);
  }
}
