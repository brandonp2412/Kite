import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class MatrixProductionProfileApi implements MatrixNativeProfileApi {
  const MatrixProductionProfileApi(this._runtime);

  final MatrixProductionRuntime _runtime;

  @override
  Future<MatrixSdkUserProfile> loadOwnProfile() async {
    final profile = await _runtime.loadOwnProfile(
      accountId: _activeAccountId(),
    );
    return _profile(profile.userId, profile.displayName, profile.avatarUrl);
  }

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) async {
    final profile = await _runtime.loadProfile(
      accountId: _activeAccountId(),
      userId: userId,
    );
    return _profile(profile.userId, profile.displayName, profile.avatarUrl);
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() {
    return _runtime.loadIgnoredUserIds(accountId: _activeAccountId());
  }

  @override
  Future<void> setUserIgnored({required String userId, required bool ignored}) {
    return _runtime.setUserIgnored(
      accountId: _activeAccountId(),
      userId: userId,
      ignored: ignored,
    );
  }

  @override
  Future<void> updateDisplayName(String displayName) {
    return _runtime.updateDisplayName(
      accountId: _activeAccountId(),
      displayName: displayName,
    );
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) {
    return _runtime.updateAvatar(
      accountId: _activeAccountId(),
      avatarUrl: avatarUri?.toString(),
    );
  }

  @override
  Future<String> openDirectMessage(String userId) {
    return _runtime.openDirectMessage(
      accountId: _activeAccountId(),
      userId: userId,
    );
  }

  String _activeAccountId() {
    final accountId = _runtime.activeAccountId.value;
    if (accountId == null) {
      throw StateError('Matrix profile operations require an active account');
    }
    return accountId;
  }

  static MatrixSdkUserProfile _profile(
    String userId,
    String? displayName,
    String? avatarUrl,
  ) {
    final avatarUri = avatarUrl == null ? null : Uri.tryParse(avatarUrl);
    if (avatarUrl != null && avatarUri == null) {
      throw StateError('Matrix profile returned an invalid avatar URI');
    }
    return MatrixSdkUserProfile(
      userId: userId,
      displayName: displayName,
      avatarUri: avatarUri,
    );
  }
}
