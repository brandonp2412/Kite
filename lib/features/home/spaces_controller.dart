import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

enum SpaceJoinOutcome { joined, failed }

enum SpaceRoomJoinState { idle, joining, joined, failed }

abstract interface class SpaceDirectoryPort {
  Future<SpaceJoinOutcome> joinRoom({
    required String spaceId,
    required String roomId,
  });
}

final class DeterministicSpaceDirectoryPort implements SpaceDirectoryPort {
  const DeterministicSpaceDirectoryPort({
    this.latency = const Duration(milliseconds: 140),
  });

  final Duration latency;

  @override
  Future<SpaceJoinOutcome> joinRoom({
    required String spaceId,
    required String roomId,
  }) async {
    await Future<void>.delayed(latency);
    return SpaceJoinOutcome.joined;
  }
}

@immutable
final class SpaceRoomPreview {
  const SpaceRoomPreview({
    required this.id,
    required this.name,
    required this.topic,
    required this.memberCount,
    this.joined = false,
  });

  final String id;
  final String name;
  final String topic;
  final int memberCount;
  final bool joined;
}

@immutable
final class SpaceSummary {
  const SpaceSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.rooms,
    this.external = false,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final List<SpaceRoomPreview> rooms;
  final bool external;
}

const deterministicSpaces = <SpaceSummary>[
  SpaceSummary(
    id: 'kite-space',
    name: 'Kite',
    description:
        'Design, engineering, releases, and the conversations around them.',
    memberCount: 42,
    rooms: <SpaceRoomPreview>[
      SpaceRoomPreview(
        id: 'kite',
        name: 'Kite',
        topic: 'Product and engineering',
        memberCount: 31,
        joined: true,
      ),
      SpaceRoomPreview(
        id: 'kite-design',
        name: 'Kite Design',
        topic: 'Screens, motion, accessibility, and visual reviews',
        memberCount: 18,
        joined: true,
      ),
      SpaceRoomPreview(
        id: 'kite-release',
        name: 'Release room',
        topic: 'Release candidates, build health, and rollout notes',
        memberCount: 12,
      ),
    ],
  ),
  SpaceSummary(
    id: 'people-space',
    name: 'People',
    description: 'A quieter place for direct conversations and small groups.',
    memberCount: 16,
    rooms: <SpaceRoomPreview>[
      SpaceRoomPreview(
        id: 'alice',
        name: 'Alice',
        topic: 'Direct conversation',
        memberCount: 2,
        joined: true,
      ),
      SpaceRoomPreview(
        id: 'bob',
        name: 'Bob',
        topic: 'Direct conversation',
        memberCount: 2,
        joined: true,
      ),
      SpaceRoomPreview(
        id: 'coffee-club',
        name: 'Coffee club',
        topic: 'Plans, places, and weekly catch-ups',
        memberCount: 9,
      ),
    ],
  ),
];

final class SpacesController {
  SpacesController({
    List<SpaceSummary> spaces = deterministicSpaces,
    SpaceDirectoryPort? port,
  }) : _spaces = signal(List<SpaceSummary>.unmodifiable(spaces)),
       _port = port ?? const DeterministicSpaceDirectoryPort(),
       selectedSpaceId = signal(spaces.firstOrNull?.id);

  final Signal<List<SpaceSummary>> _spaces;
  SpaceDirectoryPort _port;
  final Signal<String?> selectedSpaceId;
  final Map<String, Signal<SpaceRoomJoinState>> _joinStates =
      <String, Signal<SpaceRoomJoinState>>{};

  List<SpaceSummary> get spaces => _spaces.value;

  SpaceSummary? get selectedSpace {
    final id = selectedSpaceId.value;
    if (id == null) return null;
    for (final space in spaces) {
      if (space.id == id) return space;
    }
    return null;
  }

  void selectSpace(String spaceId) {
    if (!spaces.any((space) => space.id == spaceId)) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.');
    }
    if (selectedSpaceId.value == spaceId) return;
    selectedSpaceId.value = spaceId;
  }

  Signal<SpaceRoomJoinState> joinStateFor(String roomId) {
    final room = _room(roomId);
    return _joinStates.putIfAbsent(
      roomId,
      () => signal(
        room.joined ? SpaceRoomJoinState.joined : SpaceRoomJoinState.idle,
      ),
    );
  }

  Future<void> joinRoom({
    required String spaceId,
    required String roomId,
  }) async {
    final space = _space(spaceId);
    final room = space.rooms.firstWhere(
      (candidate) => candidate.id == roomId,
      orElse: () => throw ArgumentError.value(
        roomId,
        'roomId',
        'Room does not belong to Space.',
      ),
    );
    final state = joinStateFor(room.id);
    if (state.value == SpaceRoomJoinState.joining ||
        state.value == SpaceRoomJoinState.joined) {
      return;
    }
    state.value = SpaceRoomJoinState.joining;
    final outcome = await _port.joinRoom(spaceId: spaceId, roomId: roomId);
    state.value = switch (outcome) {
      SpaceJoinOutcome.joined => SpaceRoomJoinState.joined,
      SpaceJoinOutcome.failed => SpaceRoomJoinState.failed,
    };
  }

  void reconcileSpaces(List<SpaceSummary> nextSpaces) {
    final next = List<SpaceSummary>.unmodifiable(nextSpaces);
    _spaces.value = next;
    final selected = selectedSpaceId.peek();
    if (selected == null || !next.any((space) => space.id == selected)) {
      selectedSpaceId.value = next.firstOrNull?.id;
    }
    final roomIds = <String>{
      for (final space in next)
        for (final room in space.rooms) room.id,
    };
    _joinStates.removeWhere((roomId, _) => !roomIds.contains(roomId));
  }

  void reset({SpaceDirectoryPort? port}) {
    if (port != null) _port = port;
    selectedSpaceId.value = spaces.firstOrNull?.id;
    _joinStates.clear();
  }

  SpaceSummary _space(String spaceId) => spaces.firstWhere(
    (space) => space.id == spaceId,
    orElse: () =>
        throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.'),
  );

  SpaceRoomPreview _room(String roomId) {
    for (final space in spaces) {
      for (final room in space.rooms) {
        if (room.id == roomId) return room;
      }
    }
    throw ArgumentError.value(roomId, 'roomId', 'Unknown Space room.');
  }
}

final spacesController = SpacesController();
