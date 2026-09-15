import 'package:kite/matrix/matrix_sdk_boundary.dart';

final class MatrixAccountStoreRegistry {
  MatrixAccountStoreRegistry({
    required this.rootPath,
    required this.encryptionKeyIdForAccount,
  }) {
    if (rootPath.trim().isEmpty || rootPath.contains('\u0000')) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'must contain a non-empty store root without NUL bytes',
      );
    }
  }

  final String rootPath;
  final String Function(String accountId) encryptionKeyIdForAccount;

  final Map<String, MatrixSdkStoreConfiguration> _stores =
      <String, MatrixSdkStoreConfiguration>{};
  final Map<String, String> _accountByEncryptionKeyId = <String, String>{};
  final Map<String, String> _encryptionKeyIdByAccount = <String, String>{};

  MatrixSdkStoreConfiguration forAccount(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || normalizedAccountId.contains('\u0000')) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must contain a non-empty account id without NUL bytes',
      );
    }

    final existing = _stores[normalizedAccountId];
    if (existing != null) return existing;

    final encryptionKeyId = encryptionKeyIdForAccount(normalizedAccountId)
        .trim();
    if (encryptionKeyId.isEmpty || encryptionKeyId.contains('\u0000')) {
      throw StateError(
        'Matrix account store encryption key id must be non-empty and contain no NUL bytes',
      );
    }

    final retainedEncryptionKeyId =
        _encryptionKeyIdByAccount[normalizedAccountId];
    if (retainedEncryptionKeyId != null &&
        retainedEncryptionKeyId != encryptionKeyId) {
      throw StateError(
        'Matrix account stores must keep a stable encryption key per account',
      );
    }

    final keyOwner = _accountByEncryptionKeyId[encryptionKeyId];
    if (keyOwner != null && keyOwner != normalizedAccountId) {
      throw StateError(
        'Matrix account stores must not share encryption keys across accounts',
      );
    }

    final encodedAccountId = Uri.encodeComponent(normalizedAccountId);
    final normalizedRoot = rootPath.endsWith('/')
        ? rootPath.substring(0, rootPath.length - 1)
        : rootPath;
    if (normalizedRoot.isEmpty) {
      throw ArgumentError.value(rootPath, 'rootPath', 'must not be empty');
    }

    final configuration = MatrixSdkStoreConfiguration(
      accountId: normalizedAccountId,
      storePath: '$normalizedRoot/$encodedAccountId/matrix-sdk',
      encryptionKeyId: encryptionKeyId,
    );
    _stores[normalizedAccountId] = configuration;
    _accountByEncryptionKeyId[encryptionKeyId] = normalizedAccountId;
    _encryptionKeyIdByAccount[normalizedAccountId] = encryptionKeyId;
    return configuration;
  }

  bool removeAccount(String accountId) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    final removed = _stores.remove(normalizedAccountId);
    return removed != null;
  }

  bool discardUnopenedAccount(String accountId) {
    final normalizedAccountId = _normalizeAccountId(accountId);
    final removed = _stores.remove(normalizedAccountId);
    if (removed == null) return false;
    if (_accountByEncryptionKeyId[removed.encryptionKeyId] ==
        normalizedAccountId) {
      _accountByEncryptionKeyId.remove(removed.encryptionKeyId);
    }
    if (_encryptionKeyIdByAccount[normalizedAccountId] ==
        removed.encryptionKeyId) {
      _encryptionKeyIdByAccount.remove(normalizedAccountId);
    }
    return true;
  }

  static String _normalizeAccountId(String accountId) {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || normalizedAccountId.contains('\u0000')) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must contain a non-empty account id without NUL bytes',
      );
    }
    return normalizedAccountId;
  }

  Iterable<MatrixSdkStoreConfiguration> get stores =>
      List<MatrixSdkStoreConfiguration>.unmodifiable(_stores.values);
}
