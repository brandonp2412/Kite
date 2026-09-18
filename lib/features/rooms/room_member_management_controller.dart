import 'package:kite/core/async_controller_lifecycle.dart';
import 'package:kite/features/rooms/room_member_management.dart';
import 'package:signals/signals_flutter.dart';

final class RoomMemberPowerOptions {
  const RoomMemberPowerOptions({
    required this.canSetMember,
    required this.canSetModerator,
    required this.canSetAdmin,
  });

  final bool canSetMember;
  final bool canSetModerator;
  final bool canSetAdmin;
}

final class RoomMemberModerationOptions {
  const RoomMemberModerationOptions({
    required this.canKick,
    required this.canBan,
    required this.canUnban,
  });

  final bool canKick;
  final bool canBan;
  final bool canUnban;
}

final class RoomMemberManagementController with AsyncControllerLifecycle {
  RoomMemberManagementController({
    required this.roomId,
    required this._coordinator,
  });

  final String roomId;
  final RoomMemberManagementCoordinator _coordinator;

  final Signal<List<RoomMember>> members = signal<List<RoomMember>>(
    const <RoomMember>[],
  );
  final Signal<String> query = signal<String>('');
  final Signal<bool> isLoading = signal<bool>(false);
  final Signal<bool> isMutating = signal<bool>(false);
  final Signal<String?> errorMessage = signal<String?>(null);

  int _searchGeneration = 0;

  Future<void> load() => search('');

  Future<void> search(String value) async {
    if (controllerDisposed) return;
    final normalized = value.trim();
    query.value = normalized;
    final generation = ++_searchGeneration;
    isLoading.value = true;
    errorMessage.value = null;

    try {
      final result = await _coordinator.searchMembers(
        roomId: roomId,
        query: normalized,
      );
      if (generation != _searchGeneration) return;
      members.value = result;
    } catch (_) {
      if (generation != _searchGeneration) return;
      errorMessage.value = 'Kite could not load room members.';
    } finally {
      if (generation == _searchGeneration) {
        isLoading.value = false;
      }
    }
  }

  Future<bool> invite(String rawUserId) async {
    final userId = rawUserId.trim();
    if (!_isValidMatrixUserId(userId)) {
      errorMessage.value =
          'Enter a valid Matrix user ID, such as @name:server.';
      return false;
    }

    return _runMutation(
      failureMessage: 'Kite could not invite that member.',
      action: () => _coordinator.invite(roomId: roomId, userId: userId),
    );
  }

  Future<bool> reportUser(RoomMember member, {String? reason}) {
    return _runMutation(
      failureMessage: 'Kite could not report that user.',
      action: () => _coordinator.reportUser(
        roomId: roomId,
        userId: member.userId,
        reason: reason,
      ),
    );
  }

  Future<bool> reportRoom({String? reason}) {
    return _runMutation(
      failureMessage: 'Kite could not report this room.',
      action: () => _coordinator.reportRoom(roomId: roomId, reason: reason),
    );
  }

  Future<bool> leaveRoom() {
    return _runMutation(
      failureMessage: 'Kite could not leave this room.',
      action: () => _coordinator.leave(roomId: roomId),
    );
  }

  Future<bool> forgetRoom() {
    return _runMutation(
      failureMessage: 'Kite could not remove local room data.',
      action: () => _coordinator.forget(roomId: roomId),
    );
  }

  Future<RoomMemberPowerOptions> powerOptions(RoomMember member) async {
    if (member.membership != RoomMembership.joined) {
      return const RoomMemberPowerOptions(
        canSetMember: false,
        canSetModerator: false,
        canSetAdmin: false,
      );
    }

    final decisions = await Future.wait<RoomMemberActionAuthorization>(
      <Future<RoomMemberActionAuthorization>>[
        _coordinator.authorization(
          roomId: roomId,
          action: RoomMemberAction.changePowerLevel,
          targetUserId: member.userId,
          requestedPowerLevel: 0,
        ),
        _coordinator.authorization(
          roomId: roomId,
          action: RoomMemberAction.changePowerLevel,
          targetUserId: member.userId,
          requestedPowerLevel: 50,
        ),
        _coordinator.authorization(
          roomId: roomId,
          action: RoomMemberAction.changePowerLevel,
          targetUserId: member.userId,
          requestedPowerLevel: 100,
        ),
      ],
    );

    return RoomMemberPowerOptions(
      canSetMember: decisions[0].allowed,
      canSetModerator: decisions[1].allowed,
      canSetAdmin: decisions[2].allowed,
    );
  }

  Future<bool> setPowerLevel(RoomMember member, int powerLevel) async {
    final changed = await _runMutation(
      failureMessage: 'Kite could not change that member role.',
      action: () => _coordinator.setPowerLevel(
        roomId: roomId,
        userId: member.userId,
        powerLevel: powerLevel,
      ),
    );
    if (!changed) return false;

    _replaceMember(member.userId, member.copyWith(powerLevel: powerLevel));
    return true;
  }

  Future<RoomMemberModerationOptions> moderationOptions(
    RoomMember member,
  ) async {
    if (member.membership == RoomMembership.banned) {
      final decision = await _coordinator.authorization(
        roomId: roomId,
        action: RoomMemberAction.unban,
        targetUserId: member.userId,
      );
      return RoomMemberModerationOptions(
        canKick: false,
        canBan: false,
        canUnban: decision.allowed,
      );
    }

    if (member.membership != RoomMembership.joined) {
      return const RoomMemberModerationOptions(
        canKick: false,
        canBan: false,
        canUnban: false,
      );
    }

    final decisions = await Future.wait<RoomMemberActionAuthorization>(
      <Future<RoomMemberActionAuthorization>>[
        _coordinator.authorization(
          roomId: roomId,
          action: RoomMemberAction.kick,
          targetUserId: member.userId,
        ),
        _coordinator.authorization(
          roomId: roomId,
          action: RoomMemberAction.ban,
          targetUserId: member.userId,
        ),
      ],
    );
    return RoomMemberModerationOptions(
      canKick: decisions[0].allowed,
      canBan: decisions[1].allowed,
      canUnban: false,
    );
  }

  Future<bool> kick(RoomMember member) async {
    final changed = await _runMutation(
      failureMessage: 'Kite could not remove that member.',
      action: () => _coordinator.kick(roomId: roomId, userId: member.userId),
    );
    if (!changed) return false;

    _replaceMember(
      member.userId,
      member.copyWith(membership: RoomMembership.left),
    );
    return true;
  }

  Future<bool> ban(RoomMember member, {String? reason}) async {
    final changed = await _runMutation(
      failureMessage: 'Kite could not ban that member.',
      action: () => _coordinator.ban(
        roomId: roomId,
        userId: member.userId,
        reason: reason,
      ),
    );
    if (!changed) return false;

    _replaceMember(
      member.userId,
      member.copyWith(membership: RoomMembership.banned),
    );
    return true;
  }

  Future<bool> unban(RoomMember member) async {
    final changed = await _runMutation(
      failureMessage: 'Kite could not unban that member.',
      action: () => _coordinator.unban(roomId: roomId, userId: member.userId),
    );
    if (!changed) return false;

    _replaceMember(
      member.userId,
      member.copyWith(membership: RoomMembership.left),
    );
    return true;
  }

  void _replaceMember(String userId, RoomMember replacement) {
    members.value = List<RoomMember>.unmodifiable(
      members.value.map(
        (current) => current.userId == userId ? replacement : current,
      ),
    );
  }

  Future<bool> _runMutation({
    required String failureMessage,
    required Future<void> Function() action,
  }) async {
    if (controllerDisposed || isMutating.value) return false;
    final lifecycle = captureControllerLifecycle();
    isMutating.value = true;
    errorMessage.value = null;
    try {
      await action();
      return isControllerLifecycleCurrent(lifecycle);
    } on RoomMemberActionDenied catch (error) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = error.reason;
      }
      return false;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = failureMessage;
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isMutating.value = false;
      }
    }
  }

  bool _isValidMatrixUserId(String userId) {
    return userId.startsWith('@') &&
        userId.contains(':') &&
        !userId.contains(RegExp(r'\s'));
  }

  void dispose() {
    if (!disposeControllerLifecycle()) return;
    _searchGeneration += 1;
    members.dispose();
    query.dispose();
    isLoading.dispose();
    isMutating.dispose();
    errorMessage.dispose();
  }
}
