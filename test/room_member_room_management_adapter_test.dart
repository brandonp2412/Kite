import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_room_management_adapter.dart';
import 'package:kite/testing/deterministic_room_management_adapter.dart';
import 'package:kite/testing/deterministic_room_member_adapters.dart';

void main() {
  test('leave and forget use the lifecycle-aware room boundary', () async {
    final memberMutations = FakeRoomMemberMutationPort();
    final rooms = DeterministicRoomManagementPort();
    final directMetadata = DeterministicDirectRoomMetadataPort();
    final subject = LifecycleAwareRoomMemberMutationPort(
      memberMutations: memberMutations,
      roomManagement: RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: directMetadata,
      ),
    );

    await subject.leave(roomId: ' !team:example.org ');
    await subject.forget(roomId: '!team:example.org');

    expect(memberMutations.leaves, isEmpty);
    expect(memberMutations.forgottenRooms, isEmpty);
    expect(
      rooms.invocations.map((entry) => entry.type),
      <RoomManagementInvocationType>[
        RoomManagementInvocationType.leaveRoom,
        RoomManagementInvocationType.forgetRoom,
      ],
    );
    expect(directMetadata.invocations, hasLength(2));
    expect(directMetadata.invocations.first.roomId, '!team:example.org');
    expect(directMetadata.invocations.first.userIds, isEmpty);
    expect(directMetadata.invocations.last.userIds, isEmpty);
  });

  test('member mutations keep using the existing member boundary', () async {
    final memberMutations = FakeRoomMemberMutationPort();
    final subject = LifecycleAwareRoomMemberMutationPort(
      memberMutations: memberMutations,
      roomManagement: RoomManagementCoordinator(
        rooms: DeterministicRoomManagementPort(),
        directMetadata: DeterministicDirectRoomMetadataPort(),
      ),
    );

    await subject.invite(
      roomId: '!team:example.org',
      userId: '@alice:example.org',
    );
    await subject.reportRoom(roomId: '!team:example.org', reason: 'spam');

    expect(memberMutations.invitations, hasLength(1));
    expect(memberMutations.roomReports, hasLength(1));
  });

  test('failed room lifecycle work does not clear direct metadata', () async {
    final rooms = DeterministicRoomManagementPort()
      ..failNextWith = StateError('leave failed');
    final directMetadata = DeterministicDirectRoomMetadataPort();
    final subject = LifecycleAwareRoomMemberMutationPort(
      memberMutations: FakeRoomMemberMutationPort(),
      roomManagement: RoomManagementCoordinator(
        rooms: rooms,
        directMetadata: directMetadata,
      ),
    );

    await expectLater(
      subject.leave(roomId: '!team:example.org'),
      throwsStateError,
    );

    expect(directMetadata.invocations, isEmpty);
  });
}
