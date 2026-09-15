import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

void main() {
  testWidgets('home carries room and call boundaries into room details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    selectRoom('kite');
    final roomManagement = RoomManagementCoordinator(
      rooms: DeterministicRoomManagementPort(),
      directMetadata: DeterministicDirectRoomMetadataPort(),
    );
    final memberManagement = RoomMemberManagementCoordinator(
      actorUserId: '@me:example.org',
      directory: FakeRoomMemberDirectoryPort(),
      authorization: FakeRoomMemberAuthorizationPort(),
      mutations: FakeRoomMemberMutationPort(),
    );
    final calls = KiteCallCoordinator(
      gateway: DeterministicMatrixRtcGateway(),
      pictureInPicture: DeterministicPictureInPicturePort(),
      logger: StructuredLogger(
        sink: MemoryStructuredLogSink(),
        traceIds: SequenceTraceIdGenerator(seed: 400),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: HomeScreen(
          roomManagement: roomManagement,
          memberManagement: memberManagement,
          calls: calls,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-details-screen')), findsOneWidget);
    expect(find.byKey(const Key('room-call-button')), findsOneWidget);
    expect(
      find.byKey(const Key('room-members-management-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('room-settings-button')), findsOneWidget);
  });
}
