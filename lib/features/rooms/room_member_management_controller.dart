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

final class RoomMemberManagementController {
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

  Future<RoomMemberPowerOptions> powerOptions(RoomMember member) async {
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

    members.value = List<RoomMember>.unmodifiable(
      members.value.map(
        (current) => current.userId == member.userId
            ? current.copyWith(powerLevel: powerLevel)
            : current,
      ),
    );
    return true;
  }

  Future<bool> _runMutation({
    required String failureMessage,
    required Future<void> Function() action,
  }) async {
    if (isMutating.value) return false;
    isMutating.value = true;
    errorMessage.value = null;
    try {
      await action();
      return true;
    } on RoomMemberActionDenied catch (error) {
      errorMessage.value = error.reason;
      return false;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isMutating.value = false;
    }
  }

  bool _isValidMatrixUserId(String userId) {
    return userId.startsWith('@') &&
        userId.contains(':') &&
        !userId.contains(RegExp(r'\s'));
  }

  void dispose() {
    members.dispose();
    query.dispose();
    isLoading.dispose();
    isMutating.dispose();
    errorMessage.dispose();
  }
}
