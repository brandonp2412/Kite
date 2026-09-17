import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_security_runtime.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';

final class _RuntimeBoundary implements MatrixAccountSdkBoundary {
  @override
  final Set<MatrixAccountSdkCapability> accountCapabilities =
      <MatrixAccountSdkCapability>{
        MatrixAccountSdkCapability.auditedEncryption,
        MatrixAccountSdkCapability.homeserverDiscovery,
        MatrixAccountSdkCapability.accountRegistration,
        MatrixAccountSdkCapability.encryptedBackup,
      };

  int discoveryCalls = 0;
  int registrationCalls = 0;
  int recoveryCalls = 0;

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    discoveryCalls += 1;
    return MatrixSdkAuthenticationDiscovery(
      homeserver: homeserver,
      methods: const <MatrixSdkAuthenticationMethod>{},
      registrationAvailable: true,
    );
  }

  @override
  Future<MatrixSdkRegistrationStep> beginRegistration(Uri homeserver) async {
    registrationCalls += 1;
    return const MatrixSdkRegistrationStep.credentials();
  }

  @override
  Future<MatrixSdkRecoveryStatus> loadRecoveryStatus() async {
    recoveryCalls += 1;
    return const MatrixSdkRecoveryStatus(
      backupState: MatrixSdkBackupState.ready,
      historicalRecoveryState: MatrixSdkHistoricalRecoveryState.idle,
      hasUnverifiedSessions: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('all account security controllers share one SDK boundary', () async {
    final boundary = _RuntimeBoundary();
    final runtime = AccountSecurityRuntime(boundary);
    addTearDown(runtime.dispose);
    final homeserver = HomeserverAddress.parse('https://example.org');

    await runtime.authentication.discover(homeserver.toString());
    final registration = runtime.registrationFor(homeserver);
    addTearDown(registration.dispose);
    expect(await registration.begin(), isTrue);
    expect(await runtime.recovery.refresh(), isTrue);

    expect(boundary.discoveryCalls, 1);
    expect(boundary.registrationCalls, 1);
    expect(boundary.recoveryCalls, 1);
    expect(
      runtime.authentication.loginMethods.value?.registrationAvailable,
      isTrue,
    );
    expect(runtime.recovery.status.value?.backupState.name, 'ready');
    expect(runtime.recoveryAvailable, isTrue);
    expect(identical(runtime.scope.recovery, runtime.recovery), isTrue);
    expect(
      identical(runtime.scope.sessionDevices, runtime.sessionDevices),
      isTrue,
    );
    expect(identical(runtime.scope.verification, runtime.verification), isTrue);
    expect(identical(runtime.scope.profile, runtime.profile), isTrue);
  });
}
