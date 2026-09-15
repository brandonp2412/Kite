import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/calls/incoming_call.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';
import 'package:kite/testing/deterministic_incoming_call_adapter.dart';

void main() {
  test('resolves call notification through SDK state before ringing', () async {
    final fixture = _fixture();
    fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
      callId: 'rtc-42',
      roomId: '!calls:example.org',
      kind: KiteCallKind.video,
      scope: KiteCallScope.direct,
    );

    final result = await fixture.incoming.handleNotification(
      _callNotification(),
    );

    expect(result, IncomingCallNotificationResult.ringing);
    expect(fixture.calls.phase.value, KiteCallPhase.ringing);
    expect(fixture.calls.session.value?.callId, 'rtc-42');
    expect(fixture.calls.session.value?.kind, KiteCallKind.video);
    expect(fixture.resolver.resolutions, hasLength(1));
    expect(fixture.resolver.resolutions.single.accountId, 'work');
    expect(fixture.ringtone.startedCallIds, <String>['rtc-42']);
  });

  test('ignores non-call notifications without resolving SDK state', () async {
    final fixture = _fixture();
    final result = await fixture.incoming.handleNotification(
      const KiteNotification(
        id: 'message',
        kind: KiteNotificationKind.message,
        destination: AppDestination.event(
          accountId: 'work',
          roomId: '!calls:example.org',
          eventId: r'$event',
        ),
      ),
    );

    expect(result, IncomingCallNotificationResult.ignored);
    expect(fixture.resolver.resolutions, isEmpty);
    expect(fixture.calls.phase.value, KiteCallPhase.idle);
  });

  test('does not ring when SDK state says the call is unavailable', () async {
    final fixture = _fixture();

    final result = await fixture.incoming.handleNotification(
      _callNotification(),
    );

    expect(result, IncomingCallNotificationResult.unavailable);
    expect(fixture.calls.phase.value, KiteCallPhase.idle);
    expect(fixture.ringtone.startedCallIds, isEmpty);
  });

  test(
    'incoming-call surface admission requires validated RTC state',
    () async {
      final fixture = _fixture();

      expect(
        await fixture.incoming.admitNotification(_callNotification()),
        isFalse,
      );
      expect(fixture.calls.phase.value, KiteCallPhase.idle);

      fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-42',
        roomId: '!calls:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      );

      expect(
        await fixture.incoming.admitNotification(_callNotification()),
        isTrue,
      );
      expect(fixture.calls.phase.value, KiteCallPhase.ringing);
      expect(fixture.ringtone.startedCallIds, <String>['rtc-42']);
    },
  );

  test(
    'rejects resolved MatrixRTC identity that differs from push target',
    () async {
      final fixture = _fixture();
      fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
        callId: 'other-call',
        roomId: '!calls:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      );

      await expectLater(
        fixture.incoming.handleNotification(_callNotification()),
        throwsStateError,
      );

      expect(fixture.calls.phase.value, KiteCallPhase.idle);
      expect(fixture.ringtone.startedCallIds, isEmpty);
    },
  );

  test(
    'duplicate and competing call pushes are idempotent and busy-safe',
    () async {
      final fixture = _fixture();
      fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-42',
        roomId: '!calls:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.group,
      );

      expect(
        await fixture.incoming.handleNotification(_callNotification()),
        IncomingCallNotificationResult.ringing,
      );
      expect(
        await fixture.incoming.handleNotification(_callNotification()),
        IncomingCallNotificationResult.alreadyRinging,
      );
      expect(
        await fixture.incoming.handleNotification(
          _callNotification(callId: 'rtc-other'),
        ),
        IncomingCallNotificationResult.busy,
      );

      expect(fixture.resolver.resolutions, hasLength(1));
      expect(fixture.ringtone.startedCallIds, <String>['rtc-42']);
    },
  );

  test(
    'accept and decline stop ringtone only after call action succeeds',
    () async {
      final accepted = _fixture();
      accepted.resolver.descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-42',
        roomId: '!calls:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      );
      await accepted.incoming.handleNotification(_callNotification());
      await accepted.incoming.accept();

      expect(accepted.calls.phase.value, KiteCallPhase.active);
      expect(accepted.ringtone.stoppedCallIds, <String>['rtc-42']);

      final declined = _fixture();
      declined.resolver.descriptor = accepted.resolver.descriptor;
      await declined.incoming.handleNotification(_callNotification());
      await declined.incoming.decline();

      expect(declined.calls.phase.value, KiteCallPhase.ended);
      expect(declined.ringtone.stoppedCallIds, <String>['rtc-42']);

      final failed = _fixture();
      failed.resolver.descriptor = accepted.resolver.descriptor;
      await failed.incoming.handleNotification(_callNotification());
      failed.gateway.failNextWith = StateError('accept failed');

      await expectLater(failed.incoming.accept(), throwsStateError);
      expect(failed.calls.phase.value, KiteCallPhase.ringing);
      expect(failed.ringtone.stoppedCallIds, isEmpty);
    },
  );

  test('sync-ended ringing call becomes missed and stops ringtone', () async {
    final fixture = _fixture();
    fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
      callId: 'rtc-42',
      roomId: '!calls:example.org',
      kind: KiteCallKind.video,
      scope: KiteCallScope.direct,
    );
    await fixture.incoming.handleNotification(_callNotification());

    expect(await fixture.incoming.endFromSync('rtc-42'), isTrue);

    expect(fixture.calls.phase.value, KiteCallPhase.ended);
    expect(fixture.calls.session.value?.endReason, KiteCallEndReason.missed);
    expect(fixture.ringtone.stoppedCallIds, <String>['rtc-42']);
    expect(await fixture.incoming.endFromSync('rtc-42'), isFalse);
  });

  test('sync end ignores a different ringing call identity', () async {
    final fixture = _fixture();
    fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
      callId: 'rtc-42',
      roomId: '!calls:example.org',
      kind: KiteCallKind.voice,
      scope: KiteCallScope.direct,
    );
    await fixture.incoming.handleNotification(_callNotification());

    expect(await fixture.incoming.endFromSync('rtc-other'), isFalse);

    expect(fixture.calls.phase.value, KiteCallPhase.ringing);
    expect(fixture.calls.session.value?.endReason, isNull);
    expect(fixture.ringtone.stoppedCallIds, isEmpty);
  });

  test(
    'ringtone failures never hide an otherwise valid incoming call',
    () async {
      final errors = <Object>[];
      final fixture = _fixture(
        onRingtoneError: (error, _) => errors.add(error),
      );
      fixture.resolver.descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-42',
        roomId: '!calls:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.direct,
      );
      fixture.ringtone.failNextStartWith = StateError('audio unavailable');

      expect(
        await fixture.incoming.handleNotification(_callNotification()),
        IncomingCallNotificationResult.ringing,
      );

      expect(fixture.calls.phase.value, KiteCallPhase.ringing);
      expect(errors, hasLength(1));
    },
  );
}

KiteNotification _callNotification({String callId = 'rtc-42'}) {
  return KiteNotification(
    id: 'push-$callId',
    kind: KiteNotificationKind.call,
    destination: AppDestination.call(
      accountId: 'work',
      roomId: '!calls:example.org',
      callId: callId,
    ),
  );
}

_IncomingCallFixture _fixture({
  IncomingCallRingtoneErrorHandler? onRingtoneError,
}) {
  final gateway = DeterministicMatrixRtcGateway();
  final calls = KiteCallCoordinator(
    gateway: gateway,
    pictureInPicture: DeterministicPictureInPicturePort(),
    logger: StructuredLogger(
      sink: MemoryStructuredLogSink(),
      traceIds: SequenceTraceIdGenerator(seed: 440),
    ),
  );
  final resolver = DeterministicIncomingCallResolver();
  final ringtone = DeterministicIncomingCallRingtone();
  return _IncomingCallFixture(
    gateway: gateway,
    calls: calls,
    resolver: resolver,
    ringtone: ringtone,
    incoming: IncomingCallCoordinator(
      calls: calls,
      resolver: resolver,
      ringtone: ringtone,
      onRingtoneError: onRingtoneError,
    ),
  );
}

final class _IncomingCallFixture {
  const _IncomingCallFixture({
    required this.gateway,
    required this.calls,
    required this.resolver,
    required this.ringtone,
    required this.incoming,
  });

  final DeterministicMatrixRtcGateway gateway;
  final KiteCallCoordinator calls;
  final DeterministicIncomingCallResolver resolver;
  final DeterministicIncomingCallRingtone ringtone;
  final IncomingCallCoordinator incoming;
}
