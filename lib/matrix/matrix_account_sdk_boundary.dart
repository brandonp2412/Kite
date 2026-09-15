import 'package:kite/matrix/matrix_sdk_boundary.dart';

enum MatrixAccountSdkCapability {
  homeserverDiscovery,
  passwordAuthentication,
  oidcAuthentication,
  ssoAuthentication,
  qrLogin,
  accountRegistration,
  sessionPersistence,
  crossSigning,
  qrVerification,
  sasVerification,
  encryptedBackup,
  historicalMessageRecovery,
  roomEncryptionTrust,
  encryptedHistorySharing,
  deviceManagement,
  profileManagement,
  privacyControls,
  multiAccount,
}

enum MatrixSdkAuthenticationMethod { password, oidc, sso }

enum MatrixSdkRegistrationStepKind { credentials, interactive, complete }

enum MatrixSdkVerificationMethod { qr, sas }

enum MatrixSdkVerificationStage { ready, waitingForPeer, verified, cancelled }

enum MatrixSdkCrossSigningTrust { unknown, unverified, verified }

enum MatrixSdkBackupState { unknown, unavailable, ready, needsRecovery }

enum MatrixSdkHistoricalRecoveryState { idle, available, recovering, complete }

enum MatrixSdkEncryptionTrustState {
  unknown,
  verified,
  unverifiedDevice,
  unverifiedUser,
}

enum MatrixSdkDeviceVerification { verified, unverified, unknown }

final class MatrixSdkSessionDescriptor {
  const MatrixSdkSessionDescriptor({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  final String userId;
  final String deviceId;
  final Uri homeserver;

  @override
  String toString() =>
      'MatrixSdkSessionDescriptor(userId: $userId, deviceId: $deviceId, homeserver: $homeserver)';
}

final class MatrixSdkAuthenticationDiscovery {
  MatrixSdkAuthenticationDiscovery({
    required this.homeserver,
    required Set<MatrixSdkAuthenticationMethod> methods,
    this.registrationAvailable = false,
  }) : methods = Set<MatrixSdkAuthenticationMethod>.unmodifiable(methods);

  final Uri homeserver;
  final Set<MatrixSdkAuthenticationMethod> methods;
  final bool registrationAvailable;
}

final class MatrixSdkRegistrationStep {
  const MatrixSdkRegistrationStep._({
    required this.kind,
    this.publicInstructions,
    this.session,
  });

  const MatrixSdkRegistrationStep.credentials()
    : this._(kind: MatrixSdkRegistrationStepKind.credentials);

  const MatrixSdkRegistrationStep.interactive(String publicInstructions)
    : this._(
        kind: MatrixSdkRegistrationStepKind.interactive,
        publicInstructions: publicInstructions,
      );

  const MatrixSdkRegistrationStep.complete(MatrixSdkSessionDescriptor session)
    : this._(kind: MatrixSdkRegistrationStepKind.complete, session: session);

  final MatrixSdkRegistrationStepKind kind;
  final String? publicInstructions;
  final MatrixSdkSessionDescriptor? session;
}

final class MatrixSdkVerificationSession {
  MatrixSdkVerificationSession({
    required this.transactionId,
    required this.method,
    required this.stage,
    this.qrCodeData,
    List<String> sasEmoji = const <String>[],
  }) : sasEmoji = List<String>.unmodifiable(sasEmoji);

  final String transactionId;
  final MatrixSdkVerificationMethod method;
  final MatrixSdkVerificationStage stage;
  final String? qrCodeData;
  final List<String> sasEmoji;

  @override
  String toString() =>
      'MatrixSdkVerificationSession('
      'transactionId: $transactionId, method: $method, stage: $stage, '
      'qrCodeData: ${qrCodeData == null ? 'null' : '<redacted>'}, '
      'sasEmoji: ${sasEmoji.isEmpty ? '[]' : '<redacted>'})';
}

final class MatrixSdkRecoveryStatus {
  const MatrixSdkRecoveryStatus({
    required this.backupState,
    required this.historicalRecoveryState,
    required this.hasUnverifiedSessions,
  });

  final MatrixSdkBackupState backupState;
  final MatrixSdkHistoricalRecoveryState historicalRecoveryState;
  final bool hasUnverifiedSessions;
}

final class MatrixSdkRoomEncryptionTrust {
  const MatrixSdkRoomEncryptionTrust({
    required this.roomId,
    required this.isEncrypted,
    required this.trustState,
    required this.historySharingSupported,
    required this.historySharingEnabled,
  });

  final String roomId;
  final bool isEncrypted;
  final MatrixSdkEncryptionTrustState trustState;
  final bool historySharingSupported;
  final bool historySharingEnabled;
}

final class MatrixSdkDeviceDescriptor {
  const MatrixSdkDeviceDescriptor({
    required this.deviceId,
    required this.isCurrent,
    required this.verification,
    this.displayName,
    this.lastSeenAt,
  });

  final String deviceId;
  final bool isCurrent;
  final MatrixSdkDeviceVerification verification;
  final String? displayName;
  final DateTime? lastSeenAt;
}

final class MatrixSdkAccountDescriptor {
  const MatrixSdkAccountDescriptor({
    required this.accountId,
    required this.session,
    required this.isActive,
    this.displayName,
    this.avatarUri,
  });

  final String accountId;
  final MatrixSdkSessionDescriptor session;
  final bool isActive;
  final String? displayName;
  final Uri? avatarUri;
}

final class MatrixSdkUserProfile {
  const MatrixSdkUserProfile({
    required this.userId,
    this.displayName,
    this.avatarUri,
  });

  final String userId;
  final String? displayName;
  final Uri? avatarUri;
}

abstract interface class MatrixAccountSdkBoundary {
  Set<MatrixAccountSdkCapability> get accountCapabilities;

  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  );

  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  });

  Future<MatrixSdkSessionDescriptor> loginWithOidc(Uri homeserver);

  Future<MatrixSdkSessionDescriptor> loginWithSso(Uri homeserver);

  Future<MatrixSdkSessionDescriptor> loginWithQrCode(String qrCodeData);

  Future<MatrixSdkRegistrationStep> beginRegistration(Uri homeserver);

  Future<MatrixSdkRegistrationStep> submitRegistrationCredentials({
    required Uri homeserver,
    required String username,
    required String password,
  });

  Future<MatrixSdkRegistrationStep> continueRegistration(Uri homeserver);

  Future<MatrixSdkSessionDescriptor?> restoreSession();

  Future<void> persistSession(MatrixSdkSessionDescriptor session);

  Future<void> logoutSession(MatrixSdkSessionDescriptor session);

  Future<void> clearSession();

  Future<MatrixSdkCrossSigningTrust> loadCrossSigningTrust();

  Future<MatrixSdkVerificationSession> startQrVerification();

  Future<MatrixSdkVerificationSession> submitScannedQrCode(String qrCodeData);

  Future<MatrixSdkVerificationSession> confirmQrVerification(
    String transactionId,
  );

  Future<MatrixSdkVerificationSession> startSasVerification();

  Future<MatrixSdkVerificationSession> confirmSasVerification(
    String transactionId,
  );

  Future<void> cancelVerification(String transactionId);

  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus();

  Future<MatrixSdkRecoveryStatus> createEncryptedBackup();

  Future<MatrixSdkRecoveryStatus> restoreBackupWithRecoveryKey(
    String recoveryKey,
  );

  Future<MatrixSdkRecoveryStatus> restoreBackupWithPassphrase(
    String passphrase,
  );

  Future<MatrixSdkRecoveryStatus> recoverHistoricalMessages();

  Future<MatrixSdkRoomEncryptionTrust> loadRoomEncryptionTrust(String roomId);

  Future<MatrixSdkRoomEncryptionTrust> setEncryptedHistorySharing({
    required String roomId,
    required bool enabled,
  });

  Future<List<MatrixSdkDeviceDescriptor>> loadDevices();

  Future<void> signOutDevice(String deviceId);

  Future<List<MatrixSdkAccountDescriptor>> loadAccounts();

  Future<void> activateAccount(String accountId);

  Future<void> signOutAccount(String accountId);

  Future<MatrixSdkUserProfile> loadOwnProfile();

  Future<MatrixSdkUserProfile> loadProfile(String userId);

  Future<void> updateDisplayName(String displayName);

  Future<void> updateAvatar(Uri? avatarUri);

  Future<String> openDirectMessage(String userId);

  Future<Set<String>> loadIgnoredUserIds();

  Future<Set<String>> loadBlockedUserIds();

  Future<void> setUserIgnored({required String userId, required bool ignored});

  Future<void> setUserBlocked({required String userId, required bool blocked});
}

final class MatrixAccountSdkException implements Exception {
  const MatrixAccountSdkException(this.publicMessage);

  final String publicMessage;

  @override
  String toString() => 'MatrixAccountSdkException(<redacted>)';
}

void requireMatrixAccountCapability(
  MatrixAccountSdkBoundary boundary,
  MatrixAccountSdkCapability capability,
) {
  if (boundary.accountCapabilities.contains(capability)) return;
  throw MatrixSdkContractException(
    'Matrix SDK account boundary is missing required capability ${capability.name}',
  );
}
