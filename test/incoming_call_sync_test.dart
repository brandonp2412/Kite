import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/calls/incoming_call.dart';
import 'package:kite/features/calls/incoming_call_sync.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';
import 'package:kite/testing/deterministic_incoming_call_adapter.dart';

void main() {
  test('MatrixRTC sync ends the matching ringing call and ringtone', () async {
    final fixture = _fixture();
    addTearDown(fixture.source.close);
    fixture.calls.registerIncomingCall(_descriptor('call-1'));
    await fixture.ringtone.start('call-1');
    fixture.binding.start();

    fixture.source.emitEnded('call-1');
    await _flush(fixture.binding);

    expect(fixture.calls.phase.value, KiteCallPhase.ended);
    expect(fixture.calls.session.value?.endReason, KiteCallEndReason.missed);
    expect(fixture.ringtone.stoppedCallIds, <String>['call-1']);
  });

  test('sync updates stay call-id scoped and ordered', () async {
    final fixture = _fixture();
    addTearDown(fixture.source.close);
    fixture.calls.registerIncomingCall(_descriptor('call-1'));
    await fixture.ringtone.start('call-1');
    fixture.binding.start();

    fixture.source.emitEnded('other-call');
    fixture.source.emitEnded('call-1');
    await _flush(fixture.binding);

    expect(fixture.calls.phase.value, KiteCallPhase.ended);
    expect(fixture.ringtone.stoppedCallIds, <String>['call-1']);
  });

  test(
    'source errors are isolated and stopping detaches sync handling',
    () async {
      final errors = <Object>[];
      final fixture = _fixture(onError: (error, _) => errors.add(error));
      addTearDown(fixture.source.close);
      fixture.calls.registerIncomingCall(_descriptor('call-1'));
      await fixture.ringtone.start('call-1');
      fixture.binding.start();

      fixture.source.emitError(StateError('sync unavailable'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(fixture.calls.phase.value, KiteCallPhase.ringing);

      await fixture.binding.stop();
      expect(fixture.binding.isStarted, isFalse);
      fixture.source.emitEnded('call-1');
      await Future<void>.delayed(Duration.zero);

      expect(fixture.calls.phase.value, KiteCallPhase.ringing);
      expect(fixture.ringtone.stoppedCallIds, isEmpty);
    },
  );
}

Future<void> _flush(IncomingCallSyncBinding binding) async {
  await Future<void>.delayed(Duration.zero);
  await binding.flush();
}

MatrixRtcSessionDescriptor _descriptor(String callId) =>
    MatrixRtcSessionDescriptor(
      callId: callId,
      roomId: '!calls:example.org',
      kind: KiteCallKind.video,
      scope: KiteCallScope.direct,
    );

_IncomingCallSyncFixture _fixture({IncomingCallSyncErrorHandler? onError}) {
  final calls = KiteCallCoordinator(
    gateway: DeterministicMatrixRtcGateway(),
    pictureInPicture: DeterministicPictureInPicturePort(),
    logger: StructuredLogger(
      sink: MemoryStructuredLogSink(),
      traceIds: SequenceTraceIdGenerator(seed: 470),
    ),
  );
  final ringtone = DeterministicIncomingCallRingtone();
  final source = DeterministicIncomingCallSyncSource();
  final incoming = IncomingCallCoordinator(
    calls: calls,
    resolver: DeterministicIncomingCallResolver(),
    ringtone: ringtone,
  );
  return _IncomingCallSyncFixture(
    calls: calls,
    ringtone: ringtone,
    source: source,
    binding: IncomingCallSyncBinding(
      incoming: incoming,
      source: source,
      onError: onError,
    ),
  );
}

final class _IncomingCallSyncFixture {
  const _IncomingCallSyncFixture({
    required this.calls,
    required this.ringtone,
    required this.source,
    required this.binding,
  });

  final KiteCallCoordinator calls;
  final DeterministicIncomingCallRingtone ringtone;
  final DeterministicIncomingCallSyncSource source;
  final IncomingCallSyncBinding binding;
}
