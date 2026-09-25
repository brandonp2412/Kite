import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

enum SpaceJoinOutcome { joined, requested, failed }

enum SpaceRoomJoinState { idle, joining, joined, requested, failed }

abstract interface class SpaceDirectoryPort {
  Future<SpaceJoinOutcome> joinRoom({
    required String spaceId,
    required String roomId,
    required String joinRule,
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
    required String joinRule,
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
    this.joinRule = 'public',
    this.joined = false,
  });

  final String id;
  final String name;
  final String topic;
  final int memberCount;
  final String joinRule;
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
    this.childSpaceIds = const <String>[],
    this.external = false,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final List<SpaceRoomPreview> rooms;
  final List<String> childSpaceIds;
  final bool external;
}

final class _SpaceHierarchyOverlay {
  const _SpaceHierarchyOverlay({
    required this.rooms,
    required this.childSpaces,
  });

  final List<SpaceRoomPreview> rooms;
  final List<SpaceSummary> childSpaces;
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
  final Signal<Map<String, SpaceSummary>> _discoveredSpaces = signal(
    const <String, SpaceSummary>{},
  );
  final Map<String, _SpaceHierarchyOverlay> _hierarchyOverlays =
      <String, _SpaceHierarchyOverlay>{};
  SpaceDirectoryPort _port;
  final Signal<String?> selectedSpaceId;
  final Map<String, Signal<SpaceRoomJoinState>> _joinStates =
      <String, Signal<SpaceRoomJoinState>>{};

  List<SpaceSummary> get spaces => _spaces.value;

  SpaceSummary? get selectedSpace {
    final id = selectedSpaceId.value;
    if (id == null) return null;
    return _spaceOrNull(id);
  }

  SpaceSummary? spaceFor(String spaceId) => _spaceOrNull(spaceId);

  void selectSpace(String spaceId) {
    if (_spaceOrNull(spaceId) == null) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.');
    }
    if (selectedSpaceId.value == spaceId) return;
    selectedSpaceId.value = spaceId;
  }

  void updateDirectoryPort(SpaceDirectoryPort port) {
    _port = port;
  }

  List<SpaceSummary> childSpacesFor(String spaceId) {
    final space = _space(spaceId);
    final seen = <String>{};
    return List<SpaceSummary>.unmodifiable(
      space.childSpaceIds
          .where((id) => id != spaceId && seen.add(id))
          .map(_spaceOrNull)
          .whereType<SpaceSummary>(),
    );
  }

  List<SpaceSummary> parentSpacesFor(String spaceId) {
    _space(spaceId);
    final seen = <String>{};
    return List<SpaceSummary>.unmodifiable(
      <SpaceSummary>[...spaces, ..._discoveredSpaces.value.values].where(
        (space) =>
            space.id != spaceId &&
            seen.add(space.id) &&
            space.childSpaceIds.contains(spaceId),
      ),
    );
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
        state.value == SpaceRoomJoinState.joined ||
        state.value == SpaceRoomJoinState.requested) {
      return;
    }
    state.value = SpaceRoomJoinState.joining;
    final outcome = await _port.joinRoom(
      spaceId: spaceId,
      roomId: roomId,
      joinRule: room.joinRule,
    );
    state.value = switch (outcome) {
      SpaceJoinOutcome.joined => SpaceRoomJoinState.joined,
      SpaceJoinOutcome.requested => SpaceRoomJoinState.requested,
      SpaceJoinOutcome.failed => SpaceRoomJoinState.failed,
    };
  }

  void reconcileHierarchy({
    required String spaceId,
    required List<SpaceRoomPreview> rooms,
    required List<SpaceSummary> childSpaces,
  }) {
    final current = _space(spaceId);
    _hierarchyOverlays[spaceId] = _SpaceHierarchyOverlay(
      rooms: List<SpaceRoomPreview>.unmodifiable(rooms),
      childSpaces: List<SpaceSummary>.unmodifiable(childSpaces),
    );

    final discovered = Map<String, SpaceSummary>.of(_discoveredSpaces.peek());
    for (final child in childSpaces) {
      if (spaces.any((space) => space.id == child.id)) {
        discovered.remove(child.id);
      } else {
        discovered[child.id] = _applyHierarchyOverlay(child);
      }
    }

    final joinedIndex = spaces.indexWhere((space) => space.id == spaceId);
    if (joinedIndex >= 0) {
      final next = spaces.toList(growable: true);
      next[joinedIndex] = _applyHierarchyOverlay(current);
      _spaces.value = List<SpaceSummary>.unmodifiable(next);
    } else {
      discovered[spaceId] = _applyHierarchyOverlay(current);
    }
    _discoveredSpaces.value = Map<String, SpaceSummary>.unmodifiable(
      discovered,
    );
  }

  void updateSpaceDetails({
    required String spaceId,
    required String name,
    required String description,
  }) {
    final index = spaces.indexWhere((space) => space.id == spaceId);
    if (index < 0) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.');
    }
    final current = spaces[index];
    if (current.name == name && current.description == description) return;
    final next = spaces.toList(growable: true);
    next[index] = SpaceSummary(
      id: current.id,
      name: name,
      description: description,
      memberCount: current.memberCount,
      rooms: current.rooms,
      childSpaceIds: current.childSpaceIds,
      external: current.external,
    );
    _spaces.value = List<SpaceSummary>.unmodifiable(next);
  }

  void removeRoomFromSpace({required String spaceId, required String roomId}) {
    final index = spaces.indexWhere((space) => space.id == spaceId);
    if (index < 0) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.');
    }
    final current = spaces[index];
    if (!current.rooms.any((room) => room.id == roomId)) return;
    final next = spaces.toList(growable: true);
    next[index] = SpaceSummary(
      id: current.id,
      name: current.name,
      description: current.description,
      memberCount: current.memberCount,
      rooms: List<SpaceRoomPreview>.unmodifiable(
        current.rooms.where((room) => room.id != roomId),
      ),
      childSpaceIds: current.childSpaceIds,
      external: current.external,
    );
    _spaces.value = List<SpaceSummary>.unmodifiable(next);
    if (_hierarchyOverlays[spaceId] case final overlay?) {
      _hierarchyOverlays[spaceId] = _SpaceHierarchyOverlay(
        rooms: List<SpaceRoomPreview>.unmodifiable(
          overlay.rooms.where((room) => room.id != roomId),
        ),
        childSpaces: overlay.childSpaces,
      );
    }
    _joinStates.remove(roomId);
  }

  void reconcileSpaces(List<SpaceSummary> nextSpaces) {
    final joinedIds = nextSpaces.map((space) => space.id).toSet();
    final discovered = Map<String, SpaceSummary>.of(_discoveredSpaces.peek())
      ..removeWhere((spaceId, _) => joinedIds.contains(spaceId));
    final next = List<SpaceSummary>.unmodifiable(
      nextSpaces.map(_applyHierarchyOverlay),
    );
    _spaces.value = next;
    _discoveredSpaces.value = Map<String, SpaceSummary>.unmodifiable(
      discovered,
    );

    final selected = selectedSpaceId.peek();
    if (selected == null || _spaceOrNull(selected) == null) {
      selectedSpaceId.value = next.firstOrNull?.id;
    }
    final roomIds = <String>{
      for (final space in <SpaceSummary>[...next, ...discovered.values])
        for (final room in space.rooms) room.id,
    };
    _joinStates.removeWhere((roomId, _) => !roomIds.contains(roomId));
  }

  void reset({SpaceDirectoryPort? port}) {
    if (port != null) _port = port;
    selectedSpaceId.value = spaces.firstOrNull?.id;
    _joinStates.clear();
  }

  SpaceSummary _space(String spaceId) {
    final space = _spaceOrNull(spaceId);
    if (space != null) return space;
    throw ArgumentError.value(spaceId, 'spaceId', 'Unknown Space.');
  }

  SpaceSummary? _spaceOrNull(String spaceId) {
    for (final space in spaces) {
      if (space.id == spaceId) return space;
    }
    return _discoveredSpaces.value[spaceId];
  }

  SpaceRoomPreview _room(String roomId) {
    for (final space in <SpaceSummary>[
      ...spaces,
      ..._discoveredSpaces.value.values,
    ]) {
      for (final room in space.rooms) {
        if (room.id == roomId) return room;
      }
    }
    throw ArgumentError.value(roomId, 'roomId', 'Unknown Space room.');
  }

  SpaceSummary _applyHierarchyOverlay(SpaceSummary base) {
    final overlay = _hierarchyOverlays[base.id];
    if (overlay == null) return base;
    final currentRooms = <String, SpaceRoomPreview>{
      for (final room in base.rooms) room.id: room,
    };
    return SpaceSummary(
      id: base.id,
      name: base.name,
      description: base.description,
      memberCount: base.memberCount,
      rooms: <SpaceRoomPreview>[
        for (final room in overlay.rooms)
          SpaceRoomPreview(
            id: room.id,
            name: room.name,
            topic: room.topic,
            memberCount: room.memberCount,
            joinRule: room.joinRule,
            joined: room.joined || currentRooms[room.id]?.joined == true,
          ),
      ],
      childSpaceIds: <String>[
        for (final child in overlay.childSpaces) child.id,
      ],
      external: base.external,
    );
  }
}

final spacesController = SpacesController();
