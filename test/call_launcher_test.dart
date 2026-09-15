import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_launcher.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

void main() {
  testWidgets('direct room launcher starts voice and opens the call surface', (
    tester,
  ) async {
    final fixture = _fixture(seed: 10);
    await tester.pumpWidget(
      _app(
        KiteRoomCallLauncher(
          coordinator: fixture.coordinator,
          roomId: '!dm:example.org',
          roomName: 'Alice',
          isDirect: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('room-call-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call-launch-sheet')), findsOneWidget);
    expect(find.byKey(const Key('start-direct-voice-call')), findsOneWidget);
    expect(find.byKey(const Key('start-direct-video-call')), findsOneWidget);
    expect(find.byKey(const Key('start-group-video-call')), findsNothing);

    await tester.tap(find.byKey(const Key('start-direct-voice-call')));
    await tester.pumpAndSettle();

    expect(fixture.coordinator.phase.value, KiteCallPhase.active);
    expect(fixture.coordinator.session.value?.kind, KiteCallKind.voice);
    expect(fixture.coordinator.session.value?.scope, KiteCallScope.direct);
    expect(
      fixture.gateway.invocations
          .where((entry) => entry.type == MatrixRtcInvocationType.start)
          .single
          .type,
      MatrixRtcInvocationType.start,
    );
    expect(find.byKey(const Key('call-controls')), findsOneWidget);
  });

  testWidgets('group launcher joins the exact active MatrixRTC call', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      _app(
        KiteRoomCallLauncher(
          coordinator: fixture.coordinator,
          roomId: '!group:example.org',
          roomName: 'Team',
          isDirect: false,
          activeGroupCallId: 'active-element-call',
          activeGroupCallKind: KiteCallKind.voice,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('room-call-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('join-group-call')), findsOneWidget);
    expect(find.byKey(const Key('start-group-video-call')), findsNothing);

    await tester.tap(find.byKey(const Key('join-group-call')));
    await tester.pumpAndSettle();

    final invocation = fixture.gateway.invocations
        .where((entry) => entry.type == MatrixRtcInvocationType.joinGroup)
        .single;
    expect(invocation.type, MatrixRtcInvocationType.joinGroup);
    expect(invocation.callId, 'active-element-call');
    expect(invocation.kind, KiteCallKind.voice);
    expect(fixture.coordinator.session.value?.callId, 'active-element-call');
  });

  testWidgets(
    'launcher returns to the active call without creating another one',
    (tester) async {
      final fixture = _fixture(seed: 20);
      await fixture.coordinator.startDirectVideoCall('!dm:example.org');
      expect(fixture.gateway.invocations, hasLength(1));

      await tester.pumpWidget(
        _app(
          KiteRoomCallLauncher(
            coordinator: fixture.coordinator,
            roomId: '!dm:example.org',
            roomName: 'Alice',
            isDirect: true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('room-call-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-launch-sheet')), findsNothing);
      expect(find.byKey(const Key('call-controls')), findsOneWidget);
      expect(
        fixture.gateway.invocations.where(
          (entry) => entry.type == MatrixRtcInvocationType.start,
        ),
        hasLength(1),
      );
      expect(
        fixture.gateway.invocations.map((entry) => entry.type),
        containsAll(<MatrixRtcInvocationType>[
          MatrixRtcInvocationType.securityState,
          MatrixRtcInvocationType.participants,
          MatrixRtcInvocationType.availableAudioRoutes,
        ]),
      );
    },
  );

  testWidgets('launcher is disabled while another room owns the active call', (
    tester,
  ) async {
    final fixture = _fixture();
    await fixture.coordinator.startDirectVoiceCall('!other:example.org');
    await tester.pumpWidget(
      _app(
        KiteRoomCallLauncher(
          coordinator: fixture.coordinator,
          roomId: '!dm:example.org',
          roomName: 'Alice',
          isDirect: true,
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('room-call-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.byTooltip('Another call is active'), findsOneWidget);
  });
}

Widget _app(Widget launcher) {
  return MaterialApp(
    theme: KiteTheme.light,
    home: Scaffold(appBar: AppBar(actions: <Widget>[launcher])),
  );
}

_CallLauncherFixture _fixture({int seed = 0}) {
  final gateway = DeterministicMatrixRtcGateway(seed: seed);
  final coordinator = KiteCallCoordinator(
    gateway: gateway,
    pictureInPicture: DeterministicPictureInPicturePort(),
    logger: StructuredLogger(
      sink: MemoryStructuredLogSink(),
      traceIds: SequenceTraceIdGenerator(seed: 900),
    ),
  );
  return _CallLauncherFixture(gateway: gateway, coordinator: coordinator);
}

final class _CallLauncherFixture {
  const _CallLauncherFixture({
    required this.gateway,
    required this.coordinator,
  });

  final DeterministicMatrixRtcGateway gateway;
  final KiteCallCoordinator coordinator;
}
