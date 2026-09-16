import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

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
  const NativeMatrixAccountSdkBoundary(this._native);

  final MatrixNativeAuthSessionApi _native;

  @override
  Set<MatrixAccountSdkCapability> get accountCapabilities =>
      const <MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.homeserverDiscovery,
        MatrixAccountSdkCapability.passwordAuthentication,
        MatrixAccountSdkCapability.sessionPersistence,
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
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> createEncryptedBackup() =>
      _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackupWithRecoveryKey(
    String recoveryKey,
  ) => _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackupWithPassphrase(
    String passphrase,
  ) => _unsupported(MatrixAccountSdkCapability.encryptedBackup);

  @override
  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages() =>
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
      _unsupported(MatrixAccountSdkCapability.deviceManagement);

  @override
  Future<void> signOutDevice(String deviceId) =>
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
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) =>
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<void> updateDisplayName(String displayName) =>
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<void> updateAvatar(Uri? avatarUri) =>
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<String> openDirectMessage(String userId) =>
      _unsupported(MatrixAccountSdkCapability.profileManagement);

  @override
  Future<Set<String>> loadIgnoredUserIds() =>
      _unsupported(MatrixAccountSdkCapability.privacyControls);

  @override
  Future<Set<String>> loadBlockedUserIds() =>
      _unsupported(MatrixAccountSdkCapability.privacyControls);

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) => _unsupported(MatrixAccountSdkCapability.privacyControls);

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) => _unsupported(MatrixAccountSdkCapability.privacyControls);

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
