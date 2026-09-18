import 'package:signals/signals.dart';

final class MatrixUserProfile {
  const MatrixUserProfile({
    required this.userId,
    this.displayName,
    this.avatarUri,
  });

  final String userId;
  final String? displayName;
  final Uri? avatarUri;

  MatrixUserProfile copyWith({
    String? displayName,
    Uri? avatarUri,
    bool clearAvatar = false,
  }) {
    return MatrixUserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarUri: clearAvatar ? null : avatarUri ?? this.avatarUri,
    );
  }
}

abstract interface class UserProfileGateway {
  Future<MatrixUserProfile> loadOwnProfile();

  Future<MatrixUserProfile> loadProfile(String userId);

  Future<void> updateDisplayName(String displayName);

  Future<void> updateAvatar(Uri? avatarUri);

  Future<String> openDirectMessage(String userId);

  Future<Set<String>> loadIgnoredUserIds();

  Future<Set<String>> loadBlockedUserIds();

  Future<void> setUserIgnored({required String userId, required bool ignored});

  Future<void> setUserBlocked({required String userId, required bool blocked});
}

final class UserProfileController {
  UserProfileController(this._gateway);

  final UserProfileGateway _gateway;
  int _accountGeneration = 0;
  int _profileRequestGeneration = 0;

  final ownProfile = signal<MatrixUserProfile?>(null);
  final viewedProfile = signal<MatrixUserProfile?>(null);
  final ignoredUserIds = signal<Set<String>>(const <String>{});
  final blockedUserIds = signal<Set<String>>(const <String>{});
  final isLoading = signal(false);
  final isPrivacyLoading = signal(false);
  final hasPrivacyState = signal(false);
  final isSaving = signal(false);
  final errorMessage = signal<String?>(null);

  bool isIgnored(String userId) => ignoredUserIds.value.contains(userId);

  bool isBlocked(String userId) => blockedUserIds.value.contains(userId);

  Future<void> loadOwnProfile() async {
    if (isSaving.value) return;

    final generation = _accountGeneration;
    final requestGeneration = ++_profileRequestGeneration;
    isPrivacyLoading.value = false;
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final profile = await _gateway.loadOwnProfile();
      if (!_isCurrentRequest(generation, requestGeneration)) return;
      if (!_isValidProfile(profile)) {
        errorMessage.value = 'Kite received invalid profile data.';
        return;
      }
      ownProfile.value = profile;
    } catch (_) {
      if (_isCurrentRequest(generation, requestGeneration)) {
        errorMessage.value = 'Kite could not load your profile.';
      }
    } finally {
      if (_isCurrentRequest(generation, requestGeneration)) {
        isLoading.value = false;
      }
    }
  }

  Future<void> refreshPrivacyControls() async {
    if (isLoading.value || isPrivacyLoading.value || isSaving.value) return;

    final generation = _accountGeneration;
    final requestGeneration = ++_profileRequestGeneration;
    errorMessage.value = null;
    await _loadPrivacyControlsWithProgress(
      generation: generation,
      requestGeneration: requestGeneration,
    );
  }

  bool resetForAccountChange() {
    _accountGeneration += 1;
    _profileRequestGeneration += 1;
    ownProfile.value = null;
    viewedProfile.value = null;
    ignoredUserIds.value = const <String>{};
    blockedUserIds.value = const <String>{};
    isLoading.value = false;
    isPrivacyLoading.value = false;
    hasPrivacyState.value = false;
    isSaving.value = false;
    errorMessage.value = null;
    return true;
  }

  Future<void> loadUserProfile(String userId) async {
    if (isSaving.value) return;
    final generation = _accountGeneration;
    final requestGeneration = ++_profileRequestGeneration;
    isPrivacyLoading.value = false;
    if (!_isValidUserId(userId)) {
      viewedProfile.value = null;
      isLoading.value = false;
      errorMessage.value = 'That Matrix user ID is not valid.';
      return;
    }

    if (viewedProfile.value?.userId != userId) {
      viewedProfile.value = null;
    }
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final profile = await _gateway.loadProfile(userId);
      if (!_isCurrentRequest(generation, requestGeneration)) return;
      if (profile.userId != userId || !_isValidProfile(profile)) {
        errorMessage.value = 'Kite received invalid profile data.';
        return;
      }
      viewedProfile.value = profile;
      isLoading.value = false;
      await _loadPrivacyControlsWithProgress(
        generation: generation,
        requestGeneration: requestGeneration,
      );
    } catch (_) {
      if (_isCurrentRequest(generation, requestGeneration)) {
        errorMessage.value = 'Kite could not load that profile.';
      }
    } finally {
      if (_isCurrentRequest(generation, requestGeneration)) {
        isLoading.value = false;
      }
    }
  }

  Future<bool> updateDisplayName(String displayName) async {
    final current = ownProfile.value;
    if (current == null || isSaving.value || isLoading.value) return false;

    final normalized = displayName.trim();
    final generation = _accountGeneration;
    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.updateDisplayName(normalized);
      if (generation != _accountGeneration) return false;
      ownProfile.value = current.copyWith(displayName: normalized);
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not update your display name.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isSaving.value = false;
      }
    }
  }

  Future<bool> updateAvatar(Uri? avatarUri) async {
    final current = ownProfile.value;
    if (current == null || isSaving.value || isLoading.value) return false;
    if (!_isValidAvatarUri(avatarUri)) {
      errorMessage.value = 'Kite received an invalid Matrix avatar.';
      return false;
    }

    final generation = _accountGeneration;
    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.updateAvatar(avatarUri);
      if (generation != _accountGeneration) return false;
      ownProfile.value = current.copyWith(
        avatarUri: avatarUri,
        clearAvatar: avatarUri == null,
      );
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not update your avatar.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isSaving.value = false;
      }
    }
  }

  Future<String?> openDirectMessage(String userId) async {
    if (!_isValidUserId(userId) || isSaving.value || isLoading.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return null;
    }

    final generation = _accountGeneration;
    isSaving.value = true;
    errorMessage.value = null;
    try {
      final roomId = await _gateway.openDirectMessage(userId);
      if (generation != _accountGeneration) return null;
      if (!_isValidRoomId(roomId)) {
        errorMessage.value = 'Kite received an invalid direct-message room.';
        return null;
      }
      return roomId;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not open a direct message.';
      }
      return null;
    } finally {
      if (generation == _accountGeneration) {
        isSaving.value = false;
      }
    }
  }

  Future<bool> setIgnored(String userId, bool ignored) async {
    if (!_isValidUserId(userId) ||
        isSaving.value ||
        isLoading.value ||
        isPrivacyLoading.value ||
        !hasPrivacyState.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return false;
    }

    final generation = _accountGeneration;
    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.setUserIgnored(userId: userId, ignored: ignored);
      if (generation != _accountGeneration) return false;
      final next = <String>{...ignoredUserIds.value};
      if (ignored) {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      ignoredUserIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = ignored
            ? 'Kite could not ignore that user.'
            : 'Kite could not stop ignoring that user.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isSaving.value = false;
      }
    }
  }

  Future<bool> setBlocked(String userId, bool blocked) async {
    if (!_isValidUserId(userId) ||
        isSaving.value ||
        isLoading.value ||
        isPrivacyLoading.value ||
        !hasPrivacyState.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return false;
    }

    final generation = _accountGeneration;
    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.setUserBlocked(userId: userId, blocked: blocked);
      if (generation != _accountGeneration) return false;
      final next = <String>{...blockedUserIds.value};
      if (blocked) {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      blockedUserIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = blocked
            ? 'Kite could not block that user.'
            : 'Kite could not unblock that user.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isSaving.value = false;
      }
    }
  }

  Future<void> _loadPrivacyControlsWithProgress({
    required int generation,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(generation, requestGeneration)) return;
    hasPrivacyState.value = false;
    isPrivacyLoading.value = true;
    try {
      await _loadPrivacyControls(
        generation: generation,
        requestGeneration: requestGeneration,
      );
    } finally {
      if (_isCurrentRequest(generation, requestGeneration)) {
        isPrivacyLoading.value = false;
      }
    }
  }

  Future<void> _loadPrivacyControls({
    required int generation,
    required int requestGeneration,
  }) async {
    try {
      final privacy = await Future.wait<Set<String>>(<Future<Set<String>>>[
        _gateway.loadIgnoredUserIds(),
        _gateway.loadBlockedUserIds(),
      ]);
      if (!_isCurrentRequest(generation, requestGeneration)) return;
      final ignored = privacy[0];
      final blocked = privacy[1];
      if (!_areValidUserIds(ignored) || !_areValidUserIds(blocked)) {
        errorMessage.value = 'Kite received invalid privacy settings.';
        return;
      }
      ignoredUserIds.value = Set<String>.unmodifiable(ignored);
      blockedUserIds.value = Set<String>.unmodifiable(blocked);
      hasPrivacyState.value = true;
    } catch (_) {
      if (_isCurrentRequest(generation, requestGeneration)) {
        errorMessage.value = 'Kite could not load your privacy settings.';
      }
    }
  }

  bool _isCurrentRequest(int accountGeneration, int requestGeneration) {
    return accountGeneration == _accountGeneration &&
        requestGeneration == _profileRequestGeneration;
  }

  bool _isValidProfile(MatrixUserProfile profile) {
    return _isValidUserId(profile.userId) &&
        profile.userId == profile.userId.trim() &&
        _isValidAvatarUri(profile.avatarUri);
  }

  bool _isValidAvatarUri(Uri? avatarUri) {
    if (avatarUri == null) return true;
    return avatarUri.scheme == 'mxc' &&
        avatarUri.host.isNotEmpty &&
        avatarUri.userInfo.isEmpty &&
        !avatarUri.hasQuery &&
        !avatarUri.hasFragment &&
        avatarUri.pathSegments.length == 1 &&
        avatarUri.pathSegments.single.isNotEmpty;
  }

  bool _isValidRoomId(String roomId) {
    final trimmed = roomId.trim();
    final separator = trimmed.indexOf(':');
    return trimmed == roomId &&
        trimmed.startsWith('!') &&
        separator > 1 &&
        separator < trimmed.length - 1 &&
        !trimmed.contains(RegExp(r'\s'));
  }

  bool _areValidUserIds(Iterable<String> userIds) {
    for (final userId in userIds) {
      if (!_isValidUserId(userId) || userId != userId.trim()) return false;
    }
    return true;
  }

  bool _isValidUserId(String userId) {
    final trimmed = userId.trim();
    final separator = trimmed.indexOf(':');
    return trimmed == userId &&
        trimmed.startsWith('@') &&
        separator > 1 &&
        separator < trimmed.length - 1 &&
        !trimmed.contains(RegExp(r'\s'));
  }

  void dispose() {
    _accountGeneration += 1;
    _profileRequestGeneration += 1;
    ownProfile.dispose();
    viewedProfile.dispose();
    ignoredUserIds.dispose();
    blockedUserIds.dispose();
    isLoading.dispose();
    isPrivacyLoading.dispose();
    hasPrivacyState.dispose();
    isSaving.dispose();
    errorMessage.dispose();
  }
}
