import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class _AuthApi implements MatrixNativeAuthSessionApi {
  @override
  Future<void> clearSession() async {}

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async => MatrixSdkAuthenticationDiscovery(
    homeserver: homeserver,
    methods: const <MatrixSdkAuthenticationMethod>{
      MatrixSdkAuthenticationMethod.password,
    },
  );

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async => MatrixSdkSessionDescriptor(
    userId: '@alice:${homeserver.host}',
    deviceId: 'DEVICE',
    homeserver: homeserver,
  );

  @override
  Future<void> logoutSession(MatrixSdkSessionDescriptor session) async {}

  @override
  Future<void> persistSession(MatrixSdkSessionDescriptor session) async {}

  @override
  Future<MatrixSdkSessionDescriptor?> restoreSession() async => null;
}

final class _RecoveryApi implements MatrixNativeRecoveryApi {
  int createCalls = 0;
  String? restoredSecret;
  String? importedPath;
  String? importedPassphrase;
  int historyCalls = 0;

  static const status = MatrixSdkRecoveryStatus(
    backupState: MatrixSdkBackupState.ready,
    historicalRecoveryState: MatrixSdkHistoricalRecoveryState.available,
    hasUnverifiedSessions: false,
  );

  @override
  Future<MatrixSdkRecoveryStatus> createEncryptedBackup() async {
    createCalls += 1;
    return status;
  }

  @override
  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) async {
    importedPath = path;
    importedPassphrase = passphrase;
    return const MatrixSdkRoomKeyImportResult(
      importedCount: 12,
      totalCount: 14,
    );
  }

  @override
  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus() async => status;

  @override
  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages() async {
    historyCalls += 1;
    return const MatrixSdkRecoveryStatus(
      backupState: MatrixSdkBackupState.ready,
      historicalRecoveryState: MatrixSdkHistoricalRecoveryState.complete,
      hasUnverifiedSessions: false,
    );
  }

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackup(String secret) async {
    restoredSecret = secret;
    return status;
  }
}

final class _DeviceApi implements MatrixNativeDeviceApi {
  final signedOut = <(String, String)>[];

  @override
  Future<List<MatrixSdkDeviceDescriptor>> loadDevices() async =>
      const <MatrixSdkDeviceDescriptor>[
        MatrixSdkDeviceDescriptor(
          deviceId: 'CURRENT',
          isCurrent: true,
          verification: MatrixSdkDeviceVerification.verified,
          displayName: 'Glass',
        ),
        MatrixSdkDeviceDescriptor(
          deviceId: 'PHONE',
          isCurrent: false,
          verification: MatrixSdkDeviceVerification.unknown,
          displayName: 'Phone',
        ),
      ];

  @override
  Future<void> signOutDevice(
    String deviceId, {
    required String password,
  }) async {
    signedOut.add((deviceId, password));
  }
}

final class _ProfileApi implements MatrixNativeProfileApi {
  final ignored = <String>{'@spam:example.org'};
  final writes = <(String, bool)>[];

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<MatrixSdkUserProfile> loadOwnProfile() async =>
      const MatrixSdkUserProfile(userId: '@alice:example.org');

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) async =>
      MatrixSdkUserProfile(userId: userId);

  @override
  Future<String> openDirectMessage(String userId) async => '!dm:example.org';

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {
    writes.add((userId, ignored));
    if (ignored) {
      this.ignored.add(userId);
    } else {
      this.ignored.remove(userId);
    }
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}
}

void main() {
  test(
    'native profile bridge exposes Matrix ignore state as block controls',
    () async {
      final profile = _ProfileApi();
      final boundary = NativeMatrixAccountSdkBoundary(
        _AuthApi(),
        profileApi: profile,
      );

      expect(
        boundary.accountCapabilities,
        contains(MatrixAccountSdkCapability.privacyControls),
      );
      expect(await boundary.loadBlockedUserIds(), <String>{
        '@spam:example.org',
      });

      await boundary.setUserBlocked(userId: '@bob:example.org', blocked: true);
      expect(profile.writes, <(String, bool)>[('@bob:example.org', true)]);
      expect(await boundary.loadIgnoredUserIds(), contains('@bob:example.org'));

      await boundary.setUserIgnored(
        userId: '@spam:example.org',
        ignored: false,
      );
      expect(profile.writes.last, ('@spam:example.org', false));
    },
  );

  test('native recovery bridge delegates recovery actions', () async {
    final recovery = _RecoveryApi();
    final boundary = NativeMatrixAccountSdkBoundary(
      _AuthApi(),
      recoveryApi: recovery,
    );

    expect(
      boundary.accountCapabilities,
      contains(MatrixAccountSdkCapability.auditedEncryption),
    );
    expect(
      boundary.accountCapabilities,
      contains(MatrixAccountSdkCapability.encryptedBackup),
    );
    expect(
      boundary.accountCapabilities,
      contains(MatrixAccountSdkCapability.historicalMessageRecovery),
    );
    expect(await boundary.loadRecoveryStatus(), _RecoveryApi.status);
    expect(await boundary.createEncryptedBackup(), _RecoveryApi.status);
    expect(recovery.createCalls, 1);

    await boundary.restoreBackupWithRecoveryKey('opaque-secret');
    expect(recovery.restoredSecret, 'opaque-secret');
    await boundary.restoreBackupWithPassphrase('opaque passphrase');
    expect(recovery.restoredSecret, 'opaque passphrase');

    final imported = await boundary.importRoomKeyBackup(
      path: '/tmp/element-keys.txt',
      passphrase: 'export-passphrase',
    );
    expect(imported.importedCount, 12);
    expect(imported.totalCount, 14);
    expect(recovery.importedPath, '/tmp/element-keys.txt');
    expect(recovery.importedPassphrase, 'export-passphrase');

    final history = await boundary.recoverHistoricalMessages();
    expect(
      history.historicalRecoveryState,
      MatrixSdkHistoricalRecoveryState.complete,
    );
    expect(recovery.historyCalls, 1);
  });

  test('native device bridge exposes listing and remote sign-out', () async {
    final deviceApi = _DeviceApi();
    final boundary = NativeMatrixAccountSdkBoundary(
      _AuthApi(),
      deviceApi: deviceApi,
    );

    expect(
      boundary.accountCapabilities,
      contains(MatrixAccountSdkCapability.deviceListing),
    );
    expect(
      boundary.accountCapabilities,
      contains(MatrixAccountSdkCapability.deviceManagement),
    );
    final devices = await boundary.loadDevices();
    expect(devices, hasLength(2));
    expect(devices.first.deviceId, 'CURRENT');
    expect(devices.first.verification, MatrixSdkDeviceVerification.verified);

    await boundary.signOutDevice('PHONE', password: 'secret');
    expect(deviceApi.signedOut, <(String, String)>[('PHONE', 'secret')]);
  });

  test(
    'privacy controls remain unavailable without a production profile api',
    () {
      final boundary = NativeMatrixAccountSdkBoundary(_AuthApi());

      expect(
        boundary.accountCapabilities,
        isNot(contains(MatrixAccountSdkCapability.privacyControls)),
      );
      expect(
        boundary.loadBlockedUserIds(),
        throwsA(isA<MatrixSdkContractException>()),
      );
    },
  );
}
