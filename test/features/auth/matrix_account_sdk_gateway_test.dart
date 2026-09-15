import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/matrix_account_sdk_gateway.dart';
import 'package:kite/features/notifications/push_registration.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

final class _FakeAccountBoundary implements MatrixAccountSdkBoundary {
  _FakeAccountBoundary(this.accountCapabilities);

  @override
  final Set<MatrixAccountSdkCapability> accountCapabilities;

  int discoveryCalls = 0;
  int ssoCalls = 0;
  String? receivedPassword;
  String? receivedRecoveryKey;
  String? receivedVerificationQrCode;
  String? receivedDeviceToken;
  String? receivedEncryptedPayload;
  MatrixSdkPushProvider? receivedPushProvider;
  String? receivedProfileUserId;
  String? receivedDisplayName;
  Uri? receivedAvatarUri;
  int updateAvatarCalls = 0;
  String? receivedDirectMessageUserId;
  String? receivedIgnoredUserId;
  bool? receivedIgnored;
  String? receivedBlockedUserId;
  bool? receivedBlocked;
  MatrixAccountSdkException? passwordError;

  final session = MatrixSdkSessionDescriptor(
    userId: '@kite:example.org',
    deviceId: 'DEVICE',
    homeserver: Uri.parse('https://example.org'),
  );

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    discoveryCalls += 1;
    return MatrixSdkAuthenticationDiscovery(
      homeserver: homeserver,
      methods: const <MatrixSdkAuthenticationMethod>{
        MatrixSdkAuthenticationMethod.password,
        MatrixSdkAuthenticationMethod.oidc,
      },
      registrationAvailable: true,
    );
  }

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    receivedPassword = password;
    final error = passwordError;
    if (error != null) throw error;
    return session;
  }

  @override
  Future<MatrixSdkSessionDescriptor> loginWithSso(Uri homeserver) async {
    ssoCalls += 1;
    return session;
  }

  @override
  Future<MatrixSdkVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async {
    receivedVerificationQrCode = qrCodeData;
    return MatrixSdkVerificationSession(
      transactionId: 'verification-1',
      method: MatrixSdkVerificationMethod.qr,
      stage: MatrixSdkVerificationStage.waitingForPeer,
      qrCodeData: qrCodeData,
    );
  }

  @override
  Future<MatrixSdkRecoveryStatus> restoreBackupWithRecoveryKey(
    String recoveryKey,
  ) async {
    receivedRecoveryKey = recoveryKey;
    return const MatrixSdkRecoveryStatus(
      backupState: MatrixSdkBackupState.ready,
      historicalRecoveryState: MatrixSdkHistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
  }

  @override
  Future<MatrixSdkUserProfile> loadOwnProfile() async {
    return const MatrixSdkUserProfile(
      userId: '@kite:example.org',
      displayName: 'Kite User',
      avatarUri: null,
    );
  }

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) async {
    receivedProfileUserId = userId;
    return MatrixSdkUserProfile(
      userId: userId,
      displayName: 'Alice',
      avatarUri: Uri.parse('mxc://example.org/alice'),
    );
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    receivedDisplayName = displayName;
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {
    updateAvatarCalls += 1;
    receivedAvatarUri = avatarUri;
  }

  @override
  Future<String> openDirectMessage(String userId) async {
    receivedDirectMessageUserId = userId;
    return '!dm:example.org';
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{
    '@ignored:example.org',
  };

  @override
  Future<Set<String>> loadBlockedUserIds() async => <String>{
    '@blocked:example.org',
  };

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {
    receivedIgnoredUserId = userId;
    receivedIgnored = ignored;
  }

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {
    receivedBlockedUserId = userId;
    receivedBlocked = blocked;
  }

  @override
  Future<void> registerPush({
    required String accountId,
    required MatrixSdkPushProvider provider,
    required String deviceToken,
  }) async {
    receivedPushProvider = provider;
    receivedDeviceToken = deviceToken;
  }

  @override
  Future<MatrixSdkDecryptedPushNotification?> processEncryptedPushPayload({
    required String accountId,
    required String encryptedPayload,
  }) async {
    receivedEncryptedPayload = encryptedPayload;
    return const MatrixSdkDecryptedPushNotification(
      id: 'notification-1',
      kind: MatrixSdkNotificationKind.mention,
      destination: MatrixSdkNotificationDestination(
        kind: MatrixSdkNotificationDestinationKind.event,
        accountId: 'account-1',
        roomId: '!room:example.org',
        eventId: r'$event',
      ),
      title: 'Alice',
      body: 'Decrypted message body',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'authentication delegates credentials only to the SDK boundary',
    () async {
      final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.homeserverDiscovery,
        MatrixAccountSdkCapability.passwordAuthentication,
      });
      final gateway = MatrixAccountSdkGateway(boundary);
      final homeserver = HomeserverAddress.parse('example.org');

      final discovery = await gateway.discover(homeserver);
      final session = await gateway.loginWithPassword(
        homeserver: homeserver,
        username: 'kite',
        password: 'correct horse battery staple',
      );

      expect(boundary.discoveryCalls, 1);
      expect(boundary.receivedPassword, 'correct horse battery staple');
      expect(discovery.registrationAvailable, isTrue);
      expect(discovery.methods, <AuthenticationMethod>{
        AuthenticationMethod.password,
        AuthenticationMethod.oidc,
      });
      expect(session.userId, '@kite:example.org');
      expect(session.deviceId, 'DEVICE');
      expect(session.homeserver.uri, Uri.parse('https://example.org'));
    },
  );

  test(
    'missing SDK capabilities fail closed before invoking the SDK',
    () async {
      final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{});
      final gateway = MatrixAccountSdkGateway(boundary);

      await expectLater(
        gateway.loginWithSso(
          homeserver: HomeserverAddress.parse('https://example.org'),
        ),
        throwsA(isA<MatrixSdkContractException>()),
      );
      expect(boundary.ssoCalls, 0);
    },
  );

  test('cryptographic operations require an audited SDK capability', () async {
    final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{
      MatrixAccountSdkCapability.qrVerification,
    });
    final gateway = MatrixAccountSdkGateway(boundary);

    await expectLater(
      gateway.submitScannedQrCode('opaque-verification-secret'),
      throwsA(isA<MatrixSdkContractException>()),
    );
    expect(boundary.receivedVerificationQrCode, isNull);
  });

  test(
    'SDK authentication failures expose only their public message',
    () async {
      final boundary =
          _FakeAccountBoundary(<MatrixAccountSdkCapability>{
              MatrixAccountSdkCapability.passwordAuthentication,
            })
            ..passwordError = const MatrixAccountSdkException(
              'Sign in was rejected.',
            );
      final gateway = MatrixAccountSdkGateway(boundary);

      await expectLater(
        gateway.loginWithPassword(
          homeserver: HomeserverAddress.parse('https://example.org'),
          username: 'kite',
          password: 'top-secret-password',
        ),
        throwsA(
          isA<AuthenticationRejectedException>().having(
            (error) => error.publicMessage,
            'publicMessage',
            'Sign in was rejected.',
          ),
        ),
      );
      expect(
        const MatrixAccountSdkException('contains-secret-value').toString(),
        isNot(contains('contains-secret-value')),
      );
    },
  );

  test('verification and recovery secrets remain opaque SDK inputs', () async {
    final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{
      MatrixAccountSdkCapability.auditedEncryption,
      MatrixAccountSdkCapability.qrVerification,
      MatrixAccountSdkCapability.encryptedBackup,
    });
    final gateway = MatrixAccountSdkGateway(boundary);

    final verification = await gateway.submitScannedQrCode(
      'opaque-verification-secret',
    );
    final recovery = await gateway.restoreWithRecoveryKey(
      'opaque-recovery-secret',
    );

    expect(boundary.receivedVerificationQrCode, 'opaque-verification-secret');
    expect(boundary.receivedRecoveryKey, 'opaque-recovery-secret');
    expect(verification.method, DeviceVerificationMethod.qr);
    expect(verification.stage, DeviceVerificationStage.waitingForPeer);
    expect(
      verification.toString(),
      isNot(contains('opaque-verification-secret')),
    );
    expect(recovery.backupState.name, 'ready');
  });

  test(
    'profile and privacy actions stay behind SDK capability gates',
    () async {
      final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.profileManagement,
        MatrixAccountSdkCapability.privacyControls,
      });
      final gateway = MatrixAccountSdkGateway(boundary);
      final avatar = Uri.parse('mxc://example.org/new-avatar');

      final own = await gateway.loadOwnProfile();
      final other = await gateway.loadProfile('@alice:example.org');
      await gateway.updateDisplayName('Updated Name');
      await gateway.updateAvatar(avatar);
      final roomId = await gateway.openDirectMessage('@alice:example.org');
      final ignored = await gateway.loadIgnoredUserIds();
      final blocked = await gateway.loadBlockedUserIds();
      await gateway.setUserIgnored(userId: '@alice:example.org', ignored: true);
      await gateway.setUserBlocked(userId: '@alice:example.org', blocked: true);

      expect(own.userId, '@kite:example.org');
      expect(own.displayName, 'Kite User');
      expect(other.userId, '@alice:example.org');
      expect(other.avatarUri, Uri.parse('mxc://example.org/alice'));
      expect(boundary.receivedProfileUserId, '@alice:example.org');
      expect(boundary.receivedDisplayName, 'Updated Name');
      expect(boundary.updateAvatarCalls, 1);
      expect(boundary.receivedAvatarUri, avatar);
      expect(boundary.receivedDirectMessageUserId, '@alice:example.org');
      expect(roomId, '!dm:example.org');
      expect(ignored, <String>{'@ignored:example.org'});
      expect(blocked, <String>{'@blocked:example.org'});
      expect(boundary.receivedIgnoredUserId, '@alice:example.org');
      expect(boundary.receivedIgnored, isTrue);
      expect(boundary.receivedBlockedUserId, '@alice:example.org');
      expect(boundary.receivedBlocked, isTrue);
    },
  );

  test('profile calls fail closed when SDK capability is missing', () async {
    final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{});
    final gateway = MatrixAccountSdkGateway(boundary);

    await expectLater(
      gateway.loadProfile('@alice:example.org'),
      throwsA(isA<MatrixSdkContractException>()),
    );
    await expectLater(
      gateway.setUserIgnored(userId: '@alice:example.org', ignored: true),
      throwsA(isA<MatrixSdkContractException>()),
    );

    expect(boundary.receivedProfileUserId, isNull);
    expect(boundary.receivedIgnoredUserId, isNull);
  });

  test(
    'push tokens and encrypted payloads stay behind the SDK boundary',
    () async {
      final boundary = _FakeAccountBoundary(<MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.auditedEncryption,
        MatrixAccountSdkCapability.pushNotifications,
      });
      final gateway = MatrixAccountSdkGateway(boundary);

      await gateway.register(
        accountId: 'account-1',
        provider: PushProvider.fcm,
        deviceToken: 'opaque-device-token',
      );
      final decoded = await gateway.processEncryptedPayload(
        accountId: 'account-1',
        encryptedPayload: 'opaque-encrypted-payload',
      );

      expect(boundary.receivedPushProvider, MatrixSdkPushProvider.fcm);
      expect(boundary.receivedDeviceToken, 'opaque-device-token');
      expect(boundary.receivedEncryptedPayload, 'opaque-encrypted-payload');
      expect(decoded?.notification.destination.accountId, 'account-1');
      expect(decoded?.notification.destination.eventId, r'$event');
      expect(decoded?.content.title, 'Alice');
      expect(decoded?.content.body, 'Decrypted message body');
      expect(
        const MatrixSdkDecryptedPushNotification(
          id: 'n',
          kind: MatrixSdkNotificationKind.message,
          destination: MatrixSdkNotificationDestination(
            kind: MatrixSdkNotificationDestinationKind.room,
            accountId: 'a',
            roomId: '!r:example.org',
          ),
          title: 'secret title',
          body: 'secret body',
        ).toString(),
        allOf(isNot(contains('secret title')), isNot(contains('secret body'))),
      );
    },
  );
}
