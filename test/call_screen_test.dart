import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_screen.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';

void main() {
  testWidgets('incoming video call accepts into stable MatrixRTC controls', (
    tester,
  ) async {
    final fixture = _fixture();
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
        isMicrophoneMuted: false,
        isCameraEnabled: true,
        isSpeaking: false,
      ),
    ];
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'incoming-video',
        roomId: '!dm:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.direct,
      ),
    );

    await tester.pumpWidget(_app(fixture.coordinator));
    expect(find.byKey(const Key('incoming-call')), findsOneWidget);
    expect(find.text('Incoming video call'), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-accept')));
    await tester.pump();
    await tester.pump();

    expect(fixture.coordinator.phase.value, KiteCallPhase.active);
    expect(find.byKey(const Key('call-controls')), findsOneWidget);
    expect(
      find.byKey(const Key('call-participant-alice-device')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('call-participant-local-device')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('call-camera')), findsOneWidget);
    expect(find.byKey(const Key('call-switch-camera')), findsOneWidget);
    expect(find.byKey(const Key('call-audio-route')), findsOneWidget);
    expect(find.byKey(const Key('call-pip')), findsOneWidget);
    expect(find.byKey(const Key('call-security')), findsOneWidget);
    expect(
      tester
          .widget<Tooltip>(
            find.descendant(
              of: find.byKey(const Key('call-security')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      'End-to-end encrypted call',
    );

    await tester.tap(_roundButton('call-microphone'));
    await tester.pump();
    expect(fixture.coordinator.isMicrophoneMuted.value, isTrue);

    await tester.tap(_roundButton('call-camera'));
    await tester.pumpAndSettle();
    expect(
      fixture.gateway.invocations
          .where(
            (entry) => entry.type == MatrixRtcInvocationType.setCameraEnabled,
          )
          .map((entry) => entry.enabled),
      <bool?>[true],
    );
    expect(fixture.coordinator.isCameraEnabled.value, isTrue);

    await tester.tap(_roundButton('call-switch-camera'));
    await tester.pump();
    expect(fixture.coordinator.cameraFacing.value, KiteCameraFacing.rear);
    expect(
      fixture.gateway.invocations.where(
        (entry) => entry.type == MatrixRtcInvocationType.switchCamera,
      ),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('call-participant-alice-device')));
    await tester.pump();
    expect(fixture.coordinator.spotlightParticipantId.value, 'alice-device');

    await tester.tap(_roundButton('call-hang-up'));
    await tester.pump();
    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(find.byKey(const Key('call-ended')), findsOneWidget);
  });

  testWidgets('incoming voice call declines without exposing camera controls', (
    tester,
  ) async {
    final fixture = _fixture();
    fixture.coordinator.registerIncomingCall(
      const MatrixRtcSessionDescriptor(
        callId: 'incoming-voice',
        roomId: '!dm:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.direct,
      ),
    );

    await tester.pumpWidget(_app(fixture.coordinator));
    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.byKey(const Key('call-camera')), findsNothing);

    await tester.tap(_roundButton('call-decline'));
    await tester.pump();

    expect(fixture.coordinator.phase.value, KiteCallPhase.ended);
    expect(
      fixture.coordinator.session.value?.endReason,
      KiteCallEndReason.declined,
    );
    expect(find.byKey(const Key('call-ended')), findsOneWidget);
  });

  testWidgets('active call controls expose labelled accessibility targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _fixture();
    await fixture.coordinator.startDirectVideoCall('!dm:example.org');

    await tester.pumpWidget(_app(fixture.coordinator));
    await tester.pump();
    await tester.pump();

    for (final entry in <Key, String>{
      const Key('call-microphone'): 'Mute',
      const Key('call-camera'): 'Camera off',
      const Key('call-switch-camera'): 'Flip',
      const Key('call-audio-route'): 'Audio route',
      const Key('call-pip'): 'PiP',
      const Key('call-hang-up'): 'End',
    }.entries) {
      final finder = find.byKey(entry.key);
      final size = tester.getSize(finder);
      final node = tester.getSemantics(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(node.label, contains(entry.value));
    }

    semantics.dispose();
  });

  testWidgets('active voice call hydrates routes, participants, and PiP once', (
    tester,
  ) async {
    final fixture = _fixture();
    fixture.gateway.callParticipants = const <KiteCallParticipant>[
      KiteCallParticipant(
        participantId: 'local',
        userId: '@me:example.org',
        displayName: 'Me',
        isLocal: true,
        isMicrophoneMuted: false,
        isCameraEnabled: false,
        isSpeaking: false,
      ),
    ];
    await fixture.coordinator.startDirectVoiceCall('!dm:example.org');

    await tester.pumpWidget(_app(fixture.coordinator));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('call-camera')), findsNothing);
    expect(find.byKey(const Key('call-audio-route')), findsOneWidget);
    expect(find.byKey(const Key('call-pip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-audio-route')));
    await tester.pumpAndSettle();
    final routeItems = tester.widgetList<CheckedPopupMenuItem<dynamic>>(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
    );
    expect(routeItems.map((item) => item.value), <Object?>[
      'system',
      'speaker',
    ]);
    expect(routeItems.map((item) => item.checked), <bool>[false, false]);

    await tester.tap(find.byKey(const Key('call-audio-route-speaker')));
    await tester.pumpAndSettle();
    expect(fixture.coordinator.selectedAudioRouteId.value, 'speaker');

    await tester.tap(find.byKey(const Key('call-audio-route')));
    await tester.pumpAndSettle();
    final selectedItems = tester.widgetList<CheckedPopupMenuItem<dynamic>>(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
    );
    expect(selectedItems.map((item) => item.checked), <bool>[false, true]);
    Navigator.of(
      tester.element(find.byKey(const Key('call-audio-route-speaker'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(
      fixture.gateway.invocations.where(
        (entry) => entry.type == MatrixRtcInvocationType.securityState,
      ),
      hasLength(1),
    );
    expect(
      fixture.coordinator.securityState.value?.identityTrust,
      KiteCallIdentityTrust.trusted,
    );
    expect(find.byKey(const Key('call-security')), findsOneWidget);
    expect(
      fixture.gateway.invocations.where(
        (entry) => entry.type == MatrixRtcInvocationType.participants,
      ),
      hasLength(1),
    );
  });
}

Finder _roundButton(String key) => find.byKey(Key(key));

Widget _app(KiteCallCoordinator coordinator) => MaterialApp(
  theme: KiteTheme.light,
  home: KiteCallScreen(coordinator: coordinator, roomName: 'Alice'),
);

_CallFixture _fixture() {
  final gateway = DeterministicMatrixRtcGateway();
  final pictureInPicture = DeterministicPictureInPicturePort();
  return _CallFixture(
    gateway: gateway,
    coordinator: KiteCallCoordinator(
      gateway: gateway,
      pictureInPicture: pictureInPicture,
      logger: StructuredLogger(
        sink: MemoryStructuredLogSink(),
        traceIds: SequenceTraceIdGenerator(seed: 1),
      ),
    ),
  );
}

final class _CallFixture {
  const _CallFixture({required this.gateway, required this.coordinator});

  final DeterministicMatrixRtcGateway gateway;
  final KiteCallCoordinator coordinator;
}
