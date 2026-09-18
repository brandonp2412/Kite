import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/core/async_controller_lifecycle.dart';
import 'package:signals/signals.dart';

final class ManagedMatrixAccount {
  const ManagedMatrixAccount({
    required this.accountId,
    required this.session,
    required this.isActive,
    this.displayName,
    this.avatarUri,
  });

  /// Opaque local identifier for the isolated SDK/store instance.
  ///
  /// This must never contain an access token or recovery secret.
  final String accountId;
  final AuthenticatedSession session;
  final bool isActive;
  final String? displayName;
  final Uri? avatarUri;

  ManagedMatrixAccount copyWith({
    bool? isActive,
    String? displayName,
    Uri? avatarUri,
    bool clearAvatar = false,
  }) {
    return ManagedMatrixAccount(
      accountId: accountId,
      session: session,
      isActive: isActive ?? this.isActive,
      displayName: displayName ?? this.displayName,
      avatarUri: clearAvatar ? null : avatarUri ?? this.avatarUri,
    );
  }
}

abstract interface class AccountManagementGateway {
  /// Returns account metadata only. SDK credentials remain inside the SDK/store
  /// boundary and must never be surfaced through [ManagedMatrixAccount].
  Future<List<ManagedMatrixAccount>> loadAccounts();

  /// Atomically selects the account's isolated Matrix SDK/store instance.
  Future<void> activateAccount(String accountId);

  /// Invalidates the selected Matrix session and removes only that account's
  /// isolated local SDK/store data. Other accounts must remain untouched.
  Future<void> signOutAccount(String accountId);
}

final class AccountManagementController with AsyncControllerLifecycle {
  AccountManagementController(this._gateway);

  final AccountManagementGateway _gateway;

  final accounts = signal<List<ManagedMatrixAccount>>(
    const <ManagedMatrixAccount>[],
  );
  final isLoading = signal(false);
  final busyAccountIds = signal<Set<String>>(const <String>{});
  final errorMessage = signal<String?>(null);

  ManagedMatrixAccount? get activeAccount {
    for (final account in accounts.value) {
      if (account.isActive) return account;
    }
    return null;
  }

  bool get needsAccountSelection =>
      accounts.value.isNotEmpty && activeAccount == null;

  Future<bool> load() async {
    if (controllerDisposed ||
        isLoading.value ||
        busyAccountIds.value.isNotEmpty) {
      return false;
    }

    final lifecycle = captureControllerLifecycle();
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final loaded = await _gateway.loadAccounts();
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      if (!_isValidAccountList(loaded)) {
        errorMessage.value = 'Kite received invalid account information.';
        return false;
      }
      accounts.value = List<ManagedMatrixAccount>.unmodifiable(loaded);
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not load your accounts.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        isLoading.value = false;
      }
    }
  }

  Future<bool> activate(String accountId) async {
    if (controllerDisposed) return false;
    final normalized = accountId.trim();
    final account = _findAccount(normalized);
    if (account == null) {
      errorMessage.value = 'That Kite account is no longer available.';
      return false;
    }
    if (account.isActive) {
      errorMessage.value = null;
      return true;
    }
    if (!_beginAccountOperation(normalized)) return false;

    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    try {
      await _gateway.activateAccount(normalized);
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      accounts.value = List<ManagedMatrixAccount>.unmodifiable(
        accounts.value.map(
          (candidate) =>
              candidate.copyWith(isActive: candidate.accountId == normalized),
        ),
      );
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not switch accounts.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        _endAccountOperation(normalized);
      }
    }
  }

  Future<bool> signOut(String accountId) async {
    if (controllerDisposed) return false;
    final normalized = accountId.trim();
    final account = _findAccount(normalized);
    if (account == null) {
      errorMessage.value = 'That Kite account is no longer available.';
      return false;
    }
    if (!_beginAccountOperation(normalized)) return false;

    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    try {
      await _gateway.signOutAccount(normalized);
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      accounts.value = List<ManagedMatrixAccount>.unmodifiable(
        accounts.value.where((candidate) => candidate.accountId != normalized),
      );
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not sign out that account.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        _endAccountOperation(normalized);
      }
    }
  }

  ManagedMatrixAccount? _findAccount(String accountId) {
    if (accountId.isEmpty) return null;
    for (final account in accounts.value) {
      if (account.accountId == accountId) return account;
    }
    return null;
  }

  bool _beginAccountOperation(String accountId) {
    if (controllerDisposed ||
        isLoading.value ||
        busyAccountIds.value.isNotEmpty) {
      return false;
    }
    busyAccountIds.value = Set<String>.unmodifiable(<String>{
      ...busyAccountIds.value,
      accountId,
    });
    return true;
  }

  void _endAccountOperation(String accountId) {
    final remaining = <String>{...busyAccountIds.value}..remove(accountId);
    busyAccountIds.value = Set<String>.unmodifiable(remaining);
  }

  bool _isValidAccountList(List<ManagedMatrixAccount> loaded) {
    final accountIds = <String>{};
    var activeCount = 0;
    for (final account in loaded) {
      if (account.accountId.trim().isEmpty ||
          account.accountId != account.accountId.trim() ||
          account.accountId.contains(RegExp(r'\s')) ||
          !accountIds.add(account.accountId) ||
          !_isValidUserId(account.session.userId) ||
          account.session.deviceId.trim().isEmpty ||
          account.session.deviceId != account.session.deviceId.trim() ||
          !_isValidAvatarUri(account.avatarUri)) {
        return false;
      }
      if (account.isActive) activeCount += 1;
      if (activeCount > 1) return false;
    }
    return true;
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
    if (!disposeControllerLifecycle()) return;
    accounts.dispose();
    isLoading.dispose();
    busyAccountIds.dispose();
    errorMessage.dispose();
  }
}
