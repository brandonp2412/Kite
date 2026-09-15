import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/matrix_account_sdk_gateway.dart';
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
}
