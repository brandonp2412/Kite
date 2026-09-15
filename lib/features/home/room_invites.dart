import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

enum RoomInviteActionState { idle, accepting, declining, failed }

@immutable
final class RoomInvite {
  const RoomInvite({
    required this.id,
    required this.roomName,
    required this.inviterName,
    required this.memberCount,
    this.description,
    this.isExternal = false,
  });

  final String id;
  final String roomName;
  final String inviterName;
  final int memberCount;
  final String? description;
  final bool isExternal;
}

abstract interface class RoomInvitePort {
  Future<void> accept(String inviteId);
  Future<void> decline(String inviteId);
}

final class DeterministicRoomInvitePort implements RoomInvitePort {
  const DeterministicRoomInvitePort();

  @override
  Future<void> accept(String inviteId) async {}

  @override
  Future<void> decline(String inviteId) async {}
}

const deterministicRoomInvites = <RoomInvite>[
  RoomInvite(
    id: 'design-lab-invite',
    roomName: 'Design Lab',
    inviterName: 'Maya',
    memberCount: 18,
    description: 'Polish, motion, and visual review',
  ),
];

final class RoomInviteStore {
  RoomInviteStore(
    List<RoomInvite> invites, {
    this._port = const DeterministicRoomInvitePort(),
  }) : visibleInviteIds = signal<List<String>>(
         List<String>.unmodifiable(invites.map((invite) => invite.id)),
       ),
       _invites = <String, RoomInvite>{
         for (final invite in invites) invite.id: invite,
       },
       _states = <String, Signal<RoomInviteActionState>>{
         for (final invite in invites)
           invite.id: signal(RoomInviteActionState.idle),
       } {
    if (_invites.length != invites.length) {
      throw ArgumentError.value(
        invites,
        'invites',
        'Invite IDs must be unique.',
      );
    }
  }

  final RoomInvitePort _port;
  final Map<String, RoomInvite> _invites;
  final Map<String, Signal<RoomInviteActionState>> _states;
  final Signal<List<String>> visibleInviteIds;

  RoomInvite invite(String inviteId) {
    final invite = _invites[inviteId];
    if (invite == null) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Unknown invite.');
    }
    return invite;
  }

  Signal<RoomInviteActionState> stateSignal(String inviteId) {
    final state = _states[inviteId];
    if (state == null) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Unknown invite.');
    }
    return state;
  }

  Future<void> accept(String inviteId) => _act(
    inviteId,
    pending: RoomInviteActionState.accepting,
    action: _port.accept,
  );

  Future<void> decline(String inviteId) => _act(
    inviteId,
    pending: RoomInviteActionState.declining,
    action: _port.decline,
  );

  Future<void> _act(
    String inviteId, {
    required RoomInviteActionState pending,
    required Future<void> Function(String inviteId) action,
  }) async {
    final state = stateSignal(inviteId);
    if (state.value == RoomInviteActionState.accepting ||
        state.value == RoomInviteActionState.declining) {
      return;
    }
    state.value = pending;
    try {
      await action(inviteId);
      visibleInviteIds.value = List<String>.unmodifiable(
        visibleInviteIds.value.where((id) => id != inviteId),
      );
      state.value = RoomInviteActionState.idle;
    } catch (_) {
      state.value = RoomInviteActionState.failed;
    }
  }
}
