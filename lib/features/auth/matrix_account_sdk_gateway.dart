import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/features/auth/session_lifecycle.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/push_registration.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

final class MatrixAccountSdkGateway
    implements
        AuthenticationGateway,
        AccountRegistrationGateway,
        SessionLifecycleGateway,
        DeviceVerificationGateway,
        EncryptionRecoveryGateway,
        RoomKeyBackupImportGateway,
        EncryptionTrustGateway,
        SessionDeviceGateway,
        AccountManagementGateway,
        UserProfileGateway,
        PushRegistrationGateway {
  const MatrixAccountSdkGateway(this._boundary);

  final MatrixAccountSdkBoundary _boundary;

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) {
    return _authenticationAction(
      MatrixAccountSdkCapability.homeserverDiscovery,
      () async {
        final discovery = await _boundary.discoverAuthentication(
          homeserver.uri,
        );
        return HomeserverLoginMethods(
          homeserver: HomeserverAddress.parse(discovery.homeserver.toString()),
          methods: Set<AuthenticationMethod>.unmodifiable(
            discovery.methods.map(_authenticationMethod),
          ),
          registrationAvailable: discovery.registrationAvailable,
        );
      },
    );
  }

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) {
    return _authenticationAction(
      MatrixAccountSdkCapability.passwordAuthentication,
      () async => _session(
        await _boundary.loginWithPassword(
          homeserver: homeserver.uri,
          username: username,
          password: password,
        ),
      ),
    );
  }

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) {
    return _authenticationAction(
      MatrixAccountSdkCapability.oidcAuthentication,
      () async => _session(await _boundary.loginWithOidc(homeserver.uri)),
    );
  }

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) {
    return _authenticationAction(
      MatrixAccountSdkCapability.ssoAuthentication,
      () async => _session(await _boundary.loginWithSso(homeserver.uri)),
    );
  }

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) {
    return _authenticationAction(
      MatrixAccountSdkCapability.qrLogin,
      () async => _session(await _boundary.loginWithQrCode(qrCodeData)),
    );
  }

  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) {
    return _authenticationAction(
      MatrixAccountSdkCapability.accountRegistration,
      () async =>
          _registrationStep(await _boundary.beginRegistration(homeserver.uri)),
    );
  }

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) {
    return _authenticationAction(
      MatrixAccountSdkCapability.accountRegistration,
      () async => _registrationStep(
        await _boundary.submitRegistrationCredentials(
          homeserver: homeserver.uri,
          username: username,
          password: password,
        ),
      ),
    );
  }

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) {
    return _authenticationAction(
      MatrixAccountSdkCapability.accountRegistration,
      () async => _registrationStep(
        await _boundary.continueRegistration(homeserver.uri),
      ),
    );
  }

  @override
  Future<AuthenticatedSession?> restore() {
    return _run(MatrixAccountSdkCapability.sessionPersistence, () async {
      final session = await _boundary.restoreSession();
      return session == null ? null : _session(session);
    });
  }

  @override
  Future<void> persist(AuthenticatedSession session) {
    return _run(
      MatrixAccountSdkCapability.sessionPersistence,
      () => _boundary.persistSession(_sessionDescriptor(session)),
    );
  }

  @override
  Future<void> logout(AuthenticatedSession session) {
    return _run(
      MatrixAccountSdkCapability.sessionPersistence,
      () => _boundary.logoutSession(_sessionDescriptor(session)),
    );
  }

  @override
  Future<void> clear() {
    return _run(
      MatrixAccountSdkCapability.sessionPersistence,
      _boundary.clearSession,
    );
  }

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() {
    return _runAudited(
      MatrixAccountSdkCapability.crossSigning,
      () async => _crossSigningTrust(await _boundary.loadCrossSigningTrust()),
    );
  }

  @override
  Future<DeviceVerificationSession> startQrVerification() {
    return _runAudited(
      MatrixAccountSdkCapability.qrVerification,
      () async => _verificationSession(await _boundary.startQrVerification()),
    );
  }

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(String qrCodeData) {
    return _runAudited(
      MatrixAccountSdkCapability.qrVerification,
      () async =>
          _verificationSession(await _boundary.submitScannedQrCode(qrCodeData)),
    );
  }

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) {
    return _runAudited(
      MatrixAccountSdkCapability.qrVerification,
      () async => _verificationSession(
        await _boundary.confirmQrVerification(transactionId),
      ),
    );
  }

  @override
  Future<DeviceVerificationSession> startSasVerification() {
    return _runAudited(
      MatrixAccountSdkCapability.sasVerification,
      () async => _verificationSession(await _boundary.startSasVerification()),
    );
  }

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) {
    return _runAudited(
      MatrixAccountSdkCapability.sasVerification,
      () async => _verificationSession(
        await _boundary.confirmSasVerification(transactionId),
      ),
    );
  }

  @override
  Future<void> cancelVerification(String transactionId) {
    return _runAudited(
      MatrixAccountSdkCapability.crossSigning,
      () => _boundary.cancelVerification(transactionId),
    );
  }

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() {
    return _runAudited(
      MatrixAccountSdkCapability.encryptedBackup,
      () async => _recoveryStatus(await _boundary.loadRecoveryStatus()),
    );
  }

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() {
    return _runAudited(
      MatrixAccountSdkCapability.encryptedBackup,
      () async => _recoveryStatus(await _boundary.createEncryptedBackup()),
    );
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(String recoveryKey) {
    return _runAudited(
      MatrixAccountSdkCapability.encryptedBackup,
      () async => _recoveryStatus(
        await _boundary.restoreBackupWithRecoveryKey(recoveryKey),
      ),
    );
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(String passphrase) {
    return _runAudited(
      MatrixAccountSdkCapability.encryptedBackup,
      () async => _recoveryStatus(
        await _boundary.restoreBackupWithPassphrase(passphrase),
      ),
    );
  }

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() {
    return _runAudited(
      MatrixAccountSdkCapability.historicalMessageRecovery,
      () async => _recoveryStatus(await _boundary.recoverHistoricalMessages()),
    );
  }

  @override
  Future<RoomKeyBackupImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) {
    return _runAudited(
      MatrixAccountSdkCapability.historicalMessageRecovery,
      () async {
        final result = await _boundary.importRoomKeyBackup(
          path: path,
          passphrase: passphrase,
        );
        return RoomKeyBackupImportResult(
          importedCount: result.importedCount,
          totalCount: result.totalCount,
        );
      },
    );
  }

  @override
  Future<RoomEncryptionTrust> loadRoomTrust(String roomId) {
    return _runAudited(
      MatrixAccountSdkCapability.roomEncryptionTrust,
      () async => _roomTrust(await _boundary.loadRoomEncryptionTrust(roomId)),
    );
  }

  @override
  Future<RoomEncryptionTrust> setHistorySharing({
    required String roomId,
    required bool enabled,
  }) {
    return _runAudited(
      MatrixAccountSdkCapability.encryptedHistorySharing,
      () async {
        final trust = await _boundary.setEncryptedHistorySharing(
          roomId: roomId,
          enabled: enabled,
        );
        return _roomTrust(trust);
      },
    );
  }

  @override
  Future<List<SessionDevice>> loadDevices() {
    return _run(MatrixAccountSdkCapability.deviceListing, () async {
      final devices = await _boundary.loadDevices();
      return List<SessionDevice>.unmodifiable(
        devices.map(
          (device) => SessionDevice(
            deviceId: device.deviceId,
            isCurrent: device.isCurrent,
            verification: _deviceVerification(device.verification),
            displayName: device.displayName,
            lastSeenAt: device.lastSeenAt,
          ),
        ),
      );
    });
  }

  @override
  Future<void> signOutDevice(String deviceId, {required String password}) {
    return _run(
      MatrixAccountSdkCapability.deviceManagement,
      () => _boundary.signOutDevice(deviceId, password: password),
    );
  }

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() {
    return _run(MatrixAccountSdkCapability.multiAccount, () async {
      final accounts = await _boundary.loadAccounts();
      return List<ManagedMatrixAccount>.unmodifiable(
        accounts.map(
          (account) => ManagedMatrixAccount(
            accountId: account.accountId,
            session: _session(account.session),
            isActive: account.isActive,
            displayName: account.displayName,
            avatarUri: account.avatarUri,
          ),
        ),
      );
    });
  }

  @override
  Future<void> activateAccount(String accountId) {
    return _run(
      MatrixAccountSdkCapability.multiAccount,
      () => _boundary.activateAccount(accountId),
    );
  }

  @override
  Future<void> signOutAccount(String accountId) {
    return _run(
      MatrixAccountSdkCapability.multiAccount,
      () => _boundary.signOutAccount(accountId),
    );
  }

  @override
  Future<MatrixUserProfile> loadOwnProfile() {
    return _run(
      MatrixAccountSdkCapability.profileManagement,
      () async => _profile(await _boundary.loadOwnProfile()),
    );
  }

  @override
  Future<MatrixUserProfile> loadProfile(String userId) {
    return _run(
      MatrixAccountSdkCapability.profileManagement,
      () async => _profile(await _boundary.loadProfile(userId)),
    );
  }

  @override
  Future<void> updateDisplayName(String displayName) {
    return _run(
      MatrixAccountSdkCapability.profileManagement,
      () => _boundary.updateDisplayName(displayName),
    );
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) {
    return _run(
      MatrixAccountSdkCapability.profileManagement,
      () => _boundary.updateAvatar(avatarUri),
    );
  }

  @override
  Future<String> openDirectMessage(String userId) {
    return _run(
      MatrixAccountSdkCapability.profileManagement,
      () => _boundary.openDirectMessage(userId),
    );
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() {
    return _run(
      MatrixAccountSdkCapability.privacyControls,
      _boundary.loadIgnoredUserIds,
    );
  }

  @override
  Future<Set<String>> loadBlockedUserIds() {
    return _run(
      MatrixAccountSdkCapability.privacyControls,
      _boundary.loadBlockedUserIds,
    );
  }

  @override
  Future<void> setUserIgnored({required String userId, required bool ignored}) {
    return _run(
      MatrixAccountSdkCapability.privacyControls,
      () => _boundary.setUserIgnored(userId: userId, ignored: ignored),
    );
  }

  @override
  Future<void> setUserBlocked({required String userId, required bool blocked}) {
    return _run(
      MatrixAccountSdkCapability.privacyControls,
      () => _boundary.setUserBlocked(userId: userId, blocked: blocked),
    );
  }

  @override
  Future<void> register({
    required String accountId,
    required PushProvider provider,
    required String deviceToken,
  }) {
    return _run(
      MatrixAccountSdkCapability.pushNotifications,
      () => _boundary.registerPush(
        accountId: accountId,
        provider: switch (provider) {
          PushProvider.fcm => MatrixSdkPushProvider.fcm,
          PushProvider.apns => MatrixSdkPushProvider.apns,
          PushProvider.unifiedPush => MatrixSdkPushProvider.unifiedPush,
        },
        deviceToken: deviceToken,
      ),
    );
  }

  @override
  Future<void> unregister({required String accountId}) {
    return _run(
      MatrixAccountSdkCapability.pushNotifications,
      () => _boundary.unregisterPush(accountId),
    );
  }

  @override
  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) {
    return _runAudited(MatrixAccountSdkCapability.pushNotifications, () async {
      final decoded = await _boundary.processEncryptedPushPayload(
        accountId: accountId,
        encryptedPayload: encryptedPayload,
      );
      if (decoded == null) return null;
      return DecryptedPushNotification(
        notification: KiteNotification(
          id: decoded.id,
          kind: _notificationKind(decoded.kind),
          destination: _notificationDestination(decoded.destination),
        ),
        content: KiteNotificationContent(
          title: decoded.title,
          body: decoded.body,
        ),
      );
    });
  }

  Future<T> _run<T>(
    MatrixAccountSdkCapability capability,
    Future<T> Function() action,
  ) async {
    requireMatrixAccountCapability(_boundary, capability);
    return action();
  }

  Future<T> _runAudited<T>(
    MatrixAccountSdkCapability capability,
    Future<T> Function() action,
  ) async {
    requireMatrixAccountCapability(
      _boundary,
      MatrixAccountSdkCapability.auditedEncryption,
    );
    return _run(capability, action);
  }

  Future<T> _authenticationAction<T>(
    MatrixAccountSdkCapability capability,
    Future<T> Function() action,
  ) async {
    requireMatrixAccountCapability(_boundary, capability);
    try {
      return await action();
    } on MatrixAccountSdkException catch (error) {
      throw AuthenticationRejectedException(error.publicMessage);
    }
  }

  static AuthenticationMethod _authenticationMethod(
    MatrixSdkAuthenticationMethod method,
  ) => switch (method) {
    MatrixSdkAuthenticationMethod.password => AuthenticationMethod.password,
    MatrixSdkAuthenticationMethod.oidc => AuthenticationMethod.oidc,
    MatrixSdkAuthenticationMethod.sso => AuthenticationMethod.sso,
  };

  static AuthenticatedSession _session(MatrixSdkSessionDescriptor session) {
    return AuthenticatedSession(
      userId: session.userId,
      deviceId: session.deviceId,
      homeserver: HomeserverAddress.parse(session.homeserver.toString()),
    );
  }

  static MatrixSdkSessionDescriptor _sessionDescriptor(
    AuthenticatedSession session,
  ) {
    return MatrixSdkSessionDescriptor(
      userId: session.userId,
      deviceId: session.deviceId,
      homeserver: session.homeserver.uri,
    );
  }

  static AccountRegistrationStep _registrationStep(
    MatrixSdkRegistrationStep step,
  ) {
    return switch (step.kind) {
      MatrixSdkRegistrationStepKind.credentials =>
        const RegistrationCredentialsStep(),
      MatrixSdkRegistrationStepKind.interactive => RegistrationInteractiveStep(
        publicInstructions:
            step.publicInstructions ??
            (throw const MatrixSdkContractException(
              'Interactive registration step is missing public instructions',
            )),
      ),
      MatrixSdkRegistrationStepKind.complete => RegistrationCompleteStep(
        _session(
          step.session ??
              (throw const MatrixSdkContractException(
                'Completed registration step is missing session metadata',
              )),
        ),
      ),
    };
  }

  static CrossSigningTrustState _crossSigningTrust(
    MatrixSdkCrossSigningTrust trust,
  ) => switch (trust) {
    MatrixSdkCrossSigningTrust.unknown => CrossSigningTrustState.unknown,
    MatrixSdkCrossSigningTrust.unverified => CrossSigningTrustState.unverified,
    MatrixSdkCrossSigningTrust.verified => CrossSigningTrustState.verified,
  };

  static DeviceVerificationSession _verificationSession(
    MatrixSdkVerificationSession session,
  ) {
    return DeviceVerificationSession(
      transactionId: session.transactionId,
      method: switch (session.method) {
        MatrixSdkVerificationMethod.qr => DeviceVerificationMethod.qr,
        MatrixSdkVerificationMethod.sas => DeviceVerificationMethod.sas,
      },
      stage: switch (session.stage) {
        MatrixSdkVerificationStage.ready => DeviceVerificationStage.ready,
        MatrixSdkVerificationStage.waitingForPeer =>
          DeviceVerificationStage.waitingForPeer,
        MatrixSdkVerificationStage.verified => DeviceVerificationStage.verified,
        MatrixSdkVerificationStage.cancelled =>
          DeviceVerificationStage.cancelled,
      },
      qrCodeData: session.qrCodeData,
      sasEmoji: session.sasEmoji,
    );
  }

  static EncryptionRecoveryStatus _recoveryStatus(
    MatrixSdkRecoveryStatus status,
  ) {
    return EncryptionRecoveryStatus(
      backupState: switch (status.backupState) {
        MatrixSdkBackupState.unknown => EncryptedBackupState.unknown,
        MatrixSdkBackupState.unavailable => EncryptedBackupState.unavailable,
        MatrixSdkBackupState.ready => EncryptedBackupState.ready,
        MatrixSdkBackupState.needsRecovery =>
          EncryptedBackupState.needsRecovery,
      },
      historicalRecoveryState: switch (status.historicalRecoveryState) {
        MatrixSdkHistoricalRecoveryState.idle => HistoricalRecoveryState.idle,
        MatrixSdkHistoricalRecoveryState.available =>
          HistoricalRecoveryState.available,
        MatrixSdkHistoricalRecoveryState.recovering =>
          HistoricalRecoveryState.recovering,
        MatrixSdkHistoricalRecoveryState.complete =>
          HistoricalRecoveryState.complete,
      },
      hasUnverifiedSessions: status.hasUnverifiedSessions,
    );
  }

  static RoomEncryptionTrust _roomTrust(MatrixSdkRoomEncryptionTrust trust) {
    return RoomEncryptionTrust(
      roomId: trust.roomId,
      isEncrypted: trust.isEncrypted,
      trustState: switch (trust.trustState) {
        MatrixSdkEncryptionTrustState.unknown => EncryptionTrustState.unknown,
        MatrixSdkEncryptionTrustState.verified => EncryptionTrustState.verified,
        MatrixSdkEncryptionTrustState.unverifiedDevice =>
          EncryptionTrustState.unverifiedDevice,
        MatrixSdkEncryptionTrustState.unverifiedUser =>
          EncryptionTrustState.unverifiedUser,
      },
      historySharingSupported: trust.historySharingSupported,
      historySharingEnabled: trust.historySharingEnabled,
    );
  }

  static SessionDeviceVerification _deviceVerification(
    MatrixSdkDeviceVerification verification,
  ) => switch (verification) {
    MatrixSdkDeviceVerification.verified => SessionDeviceVerification.verified,
    MatrixSdkDeviceVerification.unverified =>
      SessionDeviceVerification.unverified,
    MatrixSdkDeviceVerification.unknown => SessionDeviceVerification.unknown,
  };

  static MatrixUserProfile _profile(MatrixSdkUserProfile profile) {
    return MatrixUserProfile(
      userId: profile.userId,
      displayName: profile.displayName,
      avatarUri: profile.avatarUri,
    );
  }

  static KiteNotificationKind _notificationKind(
    MatrixSdkNotificationKind kind,
  ) => switch (kind) {
    MatrixSdkNotificationKind.message => KiteNotificationKind.message,
    MatrixSdkNotificationKind.mention => KiteNotificationKind.mention,
    MatrixSdkNotificationKind.invite => KiteNotificationKind.invite,
    MatrixSdkNotificationKind.thread => KiteNotificationKind.thread,
    MatrixSdkNotificationKind.call => KiteNotificationKind.call,
  };

  static AppDestination _notificationDestination(
    MatrixSdkNotificationDestination destination,
  ) {
    return switch (destination.kind) {
      MatrixSdkNotificationDestinationKind.room => AppDestination.room(
        accountId: destination.accountId,
        roomId: destination.roomId,
      ),
      MatrixSdkNotificationDestinationKind.event => AppDestination.event(
        accountId: destination.accountId,
        roomId: destination.roomId,
        eventId:
            destination.eventId ??
            (throw const MatrixSdkContractException(
              'Event notification is missing its event ID',
            )),
      ),
      MatrixSdkNotificationDestinationKind.thread => AppDestination.thread(
        accountId: destination.accountId,
        roomId: destination.roomId,
        eventId:
            destination.eventId ??
            (throw const MatrixSdkContractException(
              'Thread notification is missing its event ID',
            )),
        threadRootEventId:
            destination.threadRootEventId ??
            (throw const MatrixSdkContractException(
              'Thread notification is missing its root event ID',
            )),
      ),
      MatrixSdkNotificationDestinationKind.call => AppDestination.call(
        accountId: destination.accountId,
        roomId: destination.roomId,
        callId:
            destination.callId ??
            (throw const MatrixSdkContractException(
              'Call notification is missing its call ID',
            )),
      ),
    };
  }
}
