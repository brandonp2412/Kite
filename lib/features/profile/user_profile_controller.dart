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

  final ownProfile = signal<MatrixUserProfile?>(null);
  final viewedProfile = signal<MatrixUserProfile?>(null);
  final ignoredUserIds = signal<Set<String>>(const <String>{});
  final blockedUserIds = signal<Set<String>>(const <String>{});
  final isLoading = signal(false);
  final isSaving = signal(false);
  final errorMessage = signal<String?>(null);

  bool isIgnored(String userId) => ignoredUserIds.value.contains(userId);

  bool isBlocked(String userId) => blockedUserIds.value.contains(userId);

  Future<void> loadOwnProfile() async {
    if (isLoading.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    try {
      ownProfile.value = await _gateway.loadOwnProfile();
      final ignored = await _gateway.loadIgnoredUserIds();
      final blocked = await _gateway.loadBlockedUserIds();
      ignoredUserIds.value = Set<String>.unmodifiable(ignored);
      blockedUserIds.value = Set<String>.unmodifiable(blocked);
    } catch (_) {
      errorMessage.value = 'Kite could not load your profile.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshPrivacyControls() async {
    if (isLoading.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    try {
      final ignored = await _gateway.loadIgnoredUserIds();
      final blocked = await _gateway.loadBlockedUserIds();
      if (!_areValidUserIds(ignored) || !_areValidUserIds(blocked)) {
        errorMessage.value = 'Kite received invalid privacy settings.';
        return;
      }
      ignoredUserIds.value = Set<String>.unmodifiable(ignored);
      blockedUserIds.value = Set<String>.unmodifiable(blocked);
    } catch (_) {
      errorMessage.value = 'Kite could not load your privacy settings.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadUserProfile(String userId) async {
    if (isLoading.value) return;
    if (!_isValidUserId(userId)) {
      errorMessage.value = 'That Matrix user ID is not valid.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = null;
    try {
      viewedProfile.value = await _gateway.loadProfile(userId);
      final ignored = await _gateway.loadIgnoredUserIds();
      final blocked = await _gateway.loadBlockedUserIds();
      ignoredUserIds.value = Set<String>.unmodifiable(ignored);
      blockedUserIds.value = Set<String>.unmodifiable(blocked);
    } catch (_) {
      errorMessage.value = 'Kite could not load that profile.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> updateDisplayName(String displayName) async {
    final current = ownProfile.value;
    if (current == null || isSaving.value) return false;

    final normalized = displayName.trim();
    if (normalized.isEmpty) {
      errorMessage.value = 'Display name cannot be empty.';
      return false;
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.updateDisplayName(normalized);
      ownProfile.value = current.copyWith(displayName: normalized);
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not update your display name.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> updateAvatar(Uri? avatarUri) async {
    final current = ownProfile.value;
    if (current == null || isSaving.value) return false;

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.updateAvatar(avatarUri);
      ownProfile.value = current.copyWith(
        avatarUri: avatarUri,
        clearAvatar: avatarUri == null,
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not update your avatar.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<String?> openDirectMessage(String userId) async {
    if (!_isValidUserId(userId) || isSaving.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return null;
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      return await _gateway.openDirectMessage(userId);
    } catch (_) {
      errorMessage.value = 'Kite could not open a direct message.';
      return null;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setIgnored(String userId, bool ignored) async {
    if (!_isValidUserId(userId) || isSaving.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return false;
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.setUserIgnored(userId: userId, ignored: ignored);
      final next = <String>{...ignoredUserIds.value};
      if (ignored) {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      ignoredUserIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      errorMessage.value = ignored
          ? 'Kite could not ignore that user.'
          : 'Kite could not stop ignoring that user.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setBlocked(String userId, bool blocked) async {
    if (!_isValidUserId(userId) || isSaving.value) {
      if (!_isValidUserId(userId)) {
        errorMessage.value = 'That Matrix user ID is not valid.';
      }
      return false;
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.setUserBlocked(userId: userId, blocked: blocked);
      final next = <String>{...blockedUserIds.value};
      if (blocked) {
        next.add(userId);
      } else {
        next.remove(userId);
      }
      blockedUserIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      errorMessage.value = blocked
          ? 'Kite could not block that user.'
          : 'Kite could not unblock that user.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  bool _areValidUserIds(Iterable<String> userIds) {
    for (final userId in userIds) {
      if (!_isValidUserId(userId) || userId != userId.trim()) return false;
    }
    return true;
  }

  bool _isValidUserId(String userId) {
    final trimmed = userId.trim();
    return trimmed.startsWith('@') &&
        trimmed.contains(':') &&
        !trimmed.contains(RegExp(r'\s'));
  }

  void dispose() {
    ownProfile.dispose();
    viewedProfile.dispose();
    ignoredUserIds.dispose();
    blockedUserIds.dispose();
    isLoading.dispose();
    isSaving.dispose();
    errorMessage.dispose();
  }
}
