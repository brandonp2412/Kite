import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

abstract interface class MatrixNativeProfileApi {
  Future<MatrixSdkUserProfile> loadOwnProfile();

  Future<MatrixSdkUserProfile> loadProfile(String userId);

  Future<Set<String>> loadIgnoredUserIds();

  Future<void> setUserIgnored({required String userId, required bool ignored});

  Future<void> updateDisplayName(String displayName);

  Future<void> updateAvatar(Uri? avatarUri);

  Future<String> openDirectMessage(String userId);
}

abstract interface class MatrixNativeRecoveryApi {
  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus();

  Future<MatrixSdkRecoveryStatus> createEncryptedBackup();

  Future<MatrixSdkRecoveryStatus> restoreBackup(String secret);

  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages();

  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  });
}

abstract interface class MatrixNativeDeviceApi {
  Future<List<MatrixSdkDeviceDescriptor>> loadDevices();

  Future<void> signOutDevice(String deviceId, {required String password});
}

abstract interface class MatrixNativeAuthSessionApi {
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  );

  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  });

  Future<MatrixSdkSessionDescriptor?> restoreSession();

  Future<void> persistSession(MatrixSdkSessionDescriptor session);

  Future<void> logoutSession(MatrixSdkSessionDescriptor session);

  Future<void> clearSession();
}

final class NativeMatrixAccountSdkBoundary implements MatrixAccountSdkBoundary {
  const NativeMatrixAccountSdkBoundary(
    this._native, {
    MatrixNativeProfileApi? profileApi,
    MatrixNativeRecoveryApi? recoveryApi,
    MatrixNativeDeviceApi? deviceApi,
  }) : _profile = profileApi,
       _recovery = recoveryApi,
       _devices = deviceApi;

  final MatrixNativeAuthSessionApi _native;
  final MatrixNativeProfileApi? _profile;
  final MatrixNativeRecoveryApi? _recovery;
  final MatrixNativeDeviceApi? _devices;

  @override
  Set<MatrixAccountSdkCapability> get accountCapabilities =>
      <MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.homeserverDiscovery,
        MatrixAccountSdkCapability.passwordAuthentication,
        MatrixAccountSdkCapability.sessionPersistence,
        MatrixAccountSdkCapability.auditedEncryption,
        if (_devices != null) ...<MatrixAccountSdkCapability>{
          MatrixAccountSdkCapability.deviceListing,
          MatrixAccountSdkCapability.deviceManagement,
        },
        if (_profile != null) ...<MatrixAccountSdkCapability>{
          MatrixAccountSdkCapability.profileManagement,
          MatrixAccountSdkCapability.privacyControls,
        },
        if (_recovery != null) ...<MatrixAccountSdkCapability>{
          MatrixAccountSdkCapability.encryptedBackup,
          MatrixAccountSdkCapability.historicalMessageRecovery,
        },
      };

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) => _native.discoverAuthentication(homeserver);

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) => _native.loginWithPassword(
    homeserver: homeserver,
    username: username,
    password: password,
  );

  @override
  Future<MatrixSdkSessionDescriptor?> restoreSession() =>
      _native.restoreSession();

  @override
  Future<void> persistSession(MatrixSdkSessionDescriptor session) =>
      _native.persistSession(session);

  @override
  Future<void> logoutSession(MatrixSdkSessionDescriptor session) =>
      _native.logoutSession(session);

  @override
  Future<void> clearSession() => _native.clearSession();

  @override
  Future<MatrixSdkSessionDescriptor> loginWithOidc(Uri homeserver) =>
      _unsupported(MatrixAccountSdkCapability.oidcAuthentication);

  @override
  Future<MatrixSdkSessionDescriptor> loginWithSso(Uri homeserver) =>
      _unsupported(MatrixAccountSdkCapability.ssoAuthentication);

  @override
  Future<MatrixSdkSessionDescriptor> loginWithQrCode(String qrCodeData) =>
      _unsupported(MatrixAccountSdkCapability.qrLogin);

  @override
  Future<MatrixSdkRegistrationStep> beginRegistration(Uri homeserver) =>
      _unsupported(MatrixAccountSdkCapability.accountRegistration);

  @override
  Future<MatrixSdkRegistrationStep> submitRegistrationCredentials({
    required Uri homeserver,
    required String username,
    required String password,
  }) => _unsupported(MatrixAccountSdkCapability.accountRegistration);

  @override
  Future<MatrixSdkRegistrationStep> continueRegistration(Uri homeserver) =>
      _unsupported(MatrixAccountSdkCapability.accountRegistration);

  @override
  Future<MatrixSdkCrossSigningTrust> loadCrossSigningTrust() =>
      _unsupported(MatrixAccountSdkCapability.crossSigning);

  @override
  Future<MatrixSdkVerificationSession> startQrVerification() =>
      _unsupported(MatrixAccountSdkCapability.qrVerification);

  @override
  Future<MatrixSdkVerificationSession> submitScannedQrCode(String qrCodeData) =>
      _unsupported(MatrixAccountSdkCapability.qrVerification);

  @override
  Future<MatrixSdkVerificationSession> confirmQrVerification(
    String transactionId,
  ) => _unsupported(MatrixAccountSdkCapability.qrVerification);

  @override
  Future<MatrixSdkVerificationSession> startSasVerification() =>
      _unsupported(MatrixAccountSdkCapability.sasVerification);

  @override
  Future<MatrixSdkVerificationSession> confirmSasVerification(
    String transactionId,
  ) => _unsupported(MatrixAccountSdkCapability.sasVerification);

  @override
  Future<void> cancelVerification(String transactionId) =>
      _unsupported(MatrixAccountSdkCapability.crossSigning);

  @override
  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus() =>
      _recovery?.loadRecoveryStatus() ??
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> createEncryptedBackup() =>
      _recovery?.createEncryptedBackup() ??
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackupWithRecoveryKey(
    String recoveryKey,
  ) =>
      _recovery?.restoreBackup(recoveryKey) ??
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackupWithPassphrase(
    String passphrase,
  ) =>
      _recovery?.restoreBackup(passphrase) ??
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages() =>
      _recovery?.recoverHistoricalMessages() ??
      _unsupported(MatrixAccountSdkCapability.historicalMessageRecovery);

  @override
  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) =>
      _recovery?.importRoomKeyBackup(path: path, passphrase: passphrase) ??
      _unsupported(MatrixAccountSdkCapability.historicalMessageRecovery);

  @override
  Future<MatrixSdkRoomEncryptionTrust> loadRoomEncryptionTrust(String roomId) =>
      _unsupported(MatrixAccountSdkCapability.roomEncryptionTrust);

  @override
  Future<MatrixSdkRoomEncryptionTrust> setEncryptedHistorySharing({
    required String roomId,
    required bool enabled,
  }) => _unsupported(MatrixAccountSdkCapability.encryptedHistorySharing);

  @override
  Future<List<MatrixSdkDeviceDescriptor>> loadDevices() =>
      _devices?.loadDevices() ??
      _unsupported(MatrixAccountSdkCapability.deviceListing);

  @override
  Future<void> signOutDevice(String deviceId, {required String password}) =>
      _devices?.signOutDevice(deviceId, password: password) ??
      _unsupported(MatrixAccountSdkCapability.deviceManagement);

  @override
  Future<List<MatrixSdkAccountDescriptor>> loadAccounts() =>
      _unsupported(MatrixAccountSdkCapability.multiAccount);

  @override
  Future<void> activateAccount(String accountId) =>
      _unsupported(MatrixAccountSdkCapability.multiAccount);

  @override
  Future<void> signOutAccount(String accountId) =>
      _unsupported(MatrixAccountSdkCapability.multiAccount);

  @override
  Future<MatrixSdkUserProfile> loadOwnProfile() =>
      _profile?.loadOwnProfile() ??
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) =>
      _profile?.loadProfile(userId) ??
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<void> updateDisplayName(String displayName) =>
      _profile?.updateDisplayName(displayName) ??
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<void> updateAvatar(Uri? avatarUri) =>
      _profile?.updateAvatar(avatarUri) ??
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<String> openDirectMessage(String userId) =>
      _profile?.openDirectMessage(userId) ??
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<Set<String>> loadIgnoredUserIds() =>
      _profile?.loadIgnoredUserIds() ??
      _unsupported(MatrixAccountSdkCapability.privacyControls);

  @override
  Future<Set<String>> loadBlockedUserIds() => loadIgnoredUserIds();

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) =>
      _profile?.setUserIgnored(userId: userId, ignored: ignored) ??
      _unsupported(MatrixAccountSdkCapability.privacyControls);

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) => setUserIgnored(userId: userId, ignored: blocked);

  @override
  Future<void> registerPush({
    required String accountId,
    required MatrixSdkPushProvider provider,
    required String deviceToken,
  }) => _unsupported(MatrixAccountSdkCapability.pushNotifications);

  @override
  Future<void> unregisterPush(String accountId) =>
      _unsupported(MatrixAccountSdkCapability.pushNotifications);

  @override
  Future<MatrixSdkDecryptedPushNotification?> processEncryptedPushPayload({
    required String accountId,
    required String encryptedPayload,
  }) => _unsupported(MatrixAccountSdkCapability.pushNotifications);

  Future<T> _unsupported<T>(MatrixAccountSdkCapability capability) {
    return Future<T>.error(
      MatrixSdkContractException(
        'Native Matrix account boundary does not expose ${capability.name}',
      ),
    );
  }
}
