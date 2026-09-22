import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_shader_warm_up.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/authentication_screen.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/device_verification_screen.dart';
import 'package:kite/features/auth/encryption_recovery_controller.dart';
import 'package:kite/features/auth/encryption_recovery_screen.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkAuthenticationGateway implements AuthenticationGateway {
  AuthenticatedSession _session(HomeserverAddress homeserver) =>
      AuthenticatedSession(
        userId: '@benchmark:${homeserver.uri.host}',
        deviceId: 'BENCHMARK_DEVICE',
        homeserver: homeserver,
      );

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async =>
      HomeserverLoginMethods(
        homeserver: homeserver,
        methods: const <AuthenticationMethod>{
          AuthenticationMethod.password,
          AuthenticationMethod.oidc,
          AuthenticationMethod.sso,
        },
        registrationAvailable: true,
      );

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) async =>
      _session(HomeserverAddress.parse('matrix.example.org'));

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);
}

final class _BenchmarkVerificationGateway implements DeviceVerificationGateway {
  var trust = CrossSigningTrustState.unverified;

  @override
  Future<void> cancelVerification(String transactionId) async {}

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) async {
    trust = CrossSigningTrustState.verified;
    return DeviceVerificationSession(
      transactionId: transactionId,
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.verified,
    );
  }

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) async {
    trust = CrossSigningTrustState.verified;
    return DeviceVerificationSession(
      transactionId: transactionId,
      method: DeviceVerificationMethod.sas,
      stage: DeviceVerificationStage.verified,
    );
  }

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() async => trust;

  @override
  Future<DeviceVerificationSession> startQrVerification() async =>
      DeviceVerificationSession(
        transactionId: 'benchmark-qr',
        method: DeviceVerificationMethod.qr,
        stage: DeviceVerificationStage.waitingForPeer,
        qrCodeData: 'opaque-benchmark-qr',
      );

  @override
  Future<DeviceVerificationSession> startSasVerification() async =>
      DeviceVerificationSession(
        transactionId: 'benchmark-sas',
        method: DeviceVerificationMethod.sas,
        stage: DeviceVerificationStage.waitingForPeer,
        sasEmoji: const <String>['🐶', '🐱', '🦁', '🐎', '🦄', '🐷', '🐘'],
      );

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async => DeviceVerificationSession(
    transactionId: 'benchmark-scanned-qr',
    method: DeviceVerificationMethod.qr,
    stage: DeviceVerificationStage.waitingForPeer,
  );
}

final class _BenchmarkRecoveryGateway implements EncryptionRecoveryGateway {
  _BenchmarkRecoveryGateway({required this.initialStatus})
    : status = initialStatus;

  final EncryptionRecoveryStatus initialStatus;
  late EncryptionRecoveryStatus status;

  @override
  Future<EncryptionRecoveryStatus> createEncryptedBackup() async {
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> loadRecoveryStatus() async => status;

  @override
  Future<EncryptionRecoveryStatus> recoverHistoricalMessages() async {
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.complete,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithPassphrase(
    String passphrase,
  ) async {
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }

  @override
  Future<EncryptionRecoveryStatus> restoreWithRecoveryKey(
    String recoveryKey,
  ) async {
    status = const EncryptionRecoveryStatus(
      backupState: EncryptedBackupState.ready,
      historicalRecoveryState: HistoricalRecoveryState.available,
      hasUnverifiedSessions: false,
    );
    return status;
  }
}

Map<String, dynamic> _record(String journey, Map<String, dynamic> result) =>
    <String, dynamic>{
      'journey': journey,
      'fixture': 'deterministic_authentication_security_v1',
      ...result,
      'result': 'PASS',
    };

void main() {
  PaintingBinding.shaderWarmUp = const KiteShaderWarmUp();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'homeserver discovery and password login have zero late Flutter frames',
    (tester) async {
      final gateway = _BenchmarkAuthenticationGateway();
      final controller = AuthenticationController(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(gateway: gateway, controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      final discoveryResult = await measureFrames(
        binding: binding,
        action: () async {
          await controller.discover('matrix.example.org');
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );
      expect(find.byKey(const Key('username-field')), findsOneWidget);
      expect(find.byKey(const Key('password-field')), findsOneWidget);

      final passwordResult = await measureFrames(
        binding: binding,
        action: () async {
          await controller.loginWithPassword(
            username: 'benchmark',
            password: 'benchmark-password',
          );
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );
      expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['homeserver_discovery'] = _record(
        'homeserver_discovery',
        discoveryResult,
      );
      binding.reportData!['password_login'] = _record(
        'password_login',
        passwordResult,
      );
    },
  );

  testWidgets('OIDC, SSO, and QR sign-in have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkAuthenticationGateway();
    final controllers = <AuthenticationController>[];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    var authGeneration = 0;

    Future<void> pumpDiscoveredAuthentication() async {
      final controller = AuthenticationController(gateway);
      controllers.add(controller);
      await controller.discover('matrix.example.org');
      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            key: ValueKey<int>(authGeneration++),
            gateway: gateway,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('oidc-login')), findsOneWidget);
      expect(find.byKey(const Key('sso-login')), findsOneWidget);
    }

    await pumpDiscoveredAuthentication();
    final oidcResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('oidc-login')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    await pumpDiscoveredAuthentication();
    final ssoResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('sso-login')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationScreen(
          key: ValueKey<int>(authGeneration++),
          gateway: gateway,
          scanQrCode: () async => 'opaque-benchmark-login-qr',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final qrResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('qr-device-login')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['oidc_login'] = _record('oidc_login', oidcResult);
    binding.reportData!['sso_login'] = _record('sso_login', ssoResult);
    binding.reportData!['qr_device_login'] = _record(
      'qr_device_login',
      qrResult,
    );
  });

  testWidgets('QR verification has zero late Flutter frames', (tester) async {
    final gateway = _BenchmarkVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);
    await controller.loadTrust();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceVerificationScreen(
          controller: controller,
          loadOnInit: false,
          qrBuilder: (context, opaquePayload) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final startResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('start-qr-verification')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    final confirmResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('confirm-qr-verification')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.trustState.value, CrossSigningTrustState.verified);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['verification_qr_start'] = _record(
      'verification_qr_start',
      startResult,
    );
    binding.reportData!['verification_qr_confirm'] = _record(
      'verification_qr_confirm',
      confirmResult,
    );
  });

  testWidgets('emoji verification has zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);
    await controller.loadTrust();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceVerificationScreen(
          controller: controller,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final startResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('start-sas-verification')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    final confirmResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('confirm-sas-verification')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.trustState.value, CrossSigningTrustState.verified);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['verification_sas_start'] = _record(
      'verification_sas_start',
      startResult,
    );
    binding.reportData!['verification_sas_confirm'] = _record(
      'verification_sas_confirm',
      confirmResult,
    );
  });

  testWidgets('backup creation has zero late Flutter frames', (tester) async {
    final gateway = _BenchmarkRecoveryGateway(
      initialStatus: const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.unavailable,
        historicalRecoveryState: HistoricalRecoveryState.idle,
        hasUnverifiedSessions: false,
      ),
    );
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: EncryptionRecoveryScreen(
          controller: controller,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('create-encrypted-backup')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.status.value?.backupState, EncryptedBackupState.ready);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['encrypted_backup_create'] = _record(
      'encrypted_backup_create',
      result,
    );
  });

  testWidgets(
    'recovery key and encrypted history recovery have zero late Flutter frames',
    (tester) async {
      final gateway = _BenchmarkRecoveryGateway(
        initialStatus: const EncryptionRecoveryStatus(
          backupState: EncryptedBackupState.needsRecovery,
          historicalRecoveryState: HistoricalRecoveryState.idle,
          hasUnverifiedSessions: true,
        ),
      );
      final controller = EncryptionRecoveryController(gateway);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: EncryptionRecoveryScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('recovery-key-field')),
        240,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('recovery-key-field')),
        'benchmark-recovery-secret',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('restore-recovery-key')),
        240,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pumpAndSettle();

      final recoveryResult = await measureFrames(
        binding: binding,
        action: () async {
          await controller.restoreWithRecoveryKey('benchmark-recovery-secret');
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('recover-history')),
        240,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pumpAndSettle();
      final historyResult = await measureFrames(
        binding: binding,
        action: () async {
          await controller.recoverHistoricalMessages();
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );
      expect(
        controller.status.value?.historicalRecoveryState,
        HistoricalRecoveryState.complete,
      );

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['recovery_key_restore'] = _record(
        'recovery_key_restore',
        recoveryResult,
      );
      binding.reportData!['encrypted_history_recovery'] = _record(
        'encrypted_history_recovery',
        historyResult,
      );
    },
  );

  testWidgets('recovery passphrase restore has zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkRecoveryGateway(
      initialStatus: const EncryptionRecoveryStatus(
        backupState: EncryptedBackupState.needsRecovery,
        historicalRecoveryState: HistoricalRecoveryState.idle,
        hasUnverifiedSessions: false,
      ),
    );
    final controller = EncryptionRecoveryController(gateway);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: EncryptionRecoveryScreen(
          controller: controller,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final otherRecoveryMethods = find.byKey(
      const Key('encryption-recovery-other-methods'),
    );
    await tester.scrollUntilVisible(
      otherRecoveryMethods,
      240,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(otherRecoveryMethods);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('recovery-passphrase-field')),
      240,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('recovery-passphrase-field')),
      'benchmark recovery passphrase',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('restore-passphrase')),
      240,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await controller.restoreWithPassphrase('benchmark recovery passphrase');
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.status.value?.backupState, EncryptedBackupState.ready);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['recovery_passphrase_restore'] = _record(
      'recovery_passphrase_restore',
      result,
    );
  });
}
