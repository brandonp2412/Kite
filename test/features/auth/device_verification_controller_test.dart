import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/device_verification_controller.dart';

final class _FakeVerificationGateway implements DeviceVerificationGateway {
  CrossSigningTrustState trust = CrossSigningTrustState.unverified;
  Object? failure;
  String? scannedQrCode;
  String? confirmedQrTransactionId;
  String? confirmedSasTransactionId;
  String? returnedQrTransactionId;
  String? returnedSasTransactionId;
  String? cancelledTransactionId;
  int trustReads = 0;
  bool confirmationUpdatesTrust = true;

  @override
  Future<void> cancelVerification(String transactionId) async {
    if (failure case final error?) throw error;
    cancelledTransactionId = transactionId;
  }

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) async {
    if (failure case final error?) throw error;
    confirmedQrTransactionId = transactionId;
    if (confirmationUpdatesTrust) {
      trust = CrossSigningTrustState.verified;
    }
    return DeviceVerificationSession(
      transactionId: returnedQrTransactionId ?? transactionId,
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.verified,
    );
  }

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) async {
    if (failure case final error?) throw error;
    confirmedSasTransactionId = transactionId;
    if (confirmationUpdatesTrust) {
      trust = CrossSigningTrustState.verified;
    }
    return DeviceVerificationSession(
      transactionId: returnedSasTransactionId ?? transactionId,
      method: DeviceVerificationMethod.sas,
      stage: DeviceVerificationStage.verified,
    );
  }

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() async {
    if (failure case final error?) throw error;
    trustReads += 1;
    return trust;
  }

  @override
  Future<DeviceVerificationSession> startQrVerification() async {
    if (failure case final error?) throw error;
    return DeviceVerificationSession(
      transactionId: 'qr-transaction',
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.ready,
      qrCodeData: 'MATRIX-VERIFICATION-SECRET',
    );
  }

  @override
  Future<DeviceVerificationSession> startSasVerification() async {
    if (failure case final error?) throw error;
    return DeviceVerificationSession(
      transactionId: 'sas-transaction',
      method: DeviceVerificationMethod.sas,
      stage: DeviceVerificationStage.ready,
      sasEmoji: const <String>['🐶', '🌳', '🚲'],
    );
  }

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async {
    if (failure case final error?) throw error;
    scannedQrCode = qrCodeData;
    return DeviceVerificationSession(
      transactionId: 'scanned-transaction',
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.waitingForPeer,
    );
  }
}

void main() {
  test('cross-signing trust drives mandatory verification state', () async {
    final gateway = _FakeVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);

    expect(controller.requiresVerification, isTrue);

    await controller.loadTrust();
    expect(controller.trustState.value, CrossSigningTrustState.unverified);
    expect(controller.requiresVerification, isTrue);

    gateway.trust = CrossSigningTrustState.verified;
    await controller.loadTrust();
    expect(controller.requiresVerification, isFalse);
  });

  test('trust refresh failure fails closed after a verified state', () async {
    final gateway = _FakeVerificationGateway()
      ..trust = CrossSigningTrustState.verified;
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);

    await controller.loadTrust();
    expect(controller.requiresVerification, isFalse);

    gateway.failure = StateError('access_token=secret');
    await controller.loadTrust();

    expect(controller.trustState.value, CrossSigningTrustState.unknown);
    expect(controller.requiresVerification, isTrue);
    expect(
      controller.errorMessage.value,
      'Kite could not read device verification status.',
    );
    expect(controller.errorMessage.value, isNot(contains('secret')));
  });

  test('verification session rejects malformed transaction metadata', () {
    expect(
      () => DeviceVerificationSession(
        transactionId: ' bad transaction ',
        method: DeviceVerificationMethod.qr,
        stage: DeviceVerificationStage.ready,
      ),
      throwsArgumentError,
    );
    expect(
      () => DeviceVerificationSession(
        transactionId: 'qr-transaction',
        method: DeviceVerificationMethod.qr,
        stage: DeviceVerificationStage.ready,
        qrCodeData: '   ',
      ),
      throwsArgumentError,
    );
    expect(
      () => DeviceVerificationSession(
        transactionId: 'sas-transaction',
        method: DeviceVerificationMethod.sas,
        stage: DeviceVerificationStage.ready,
        sasEmoji: const <String>['🐶', ''],
      ),
      throwsArgumentError,
    );
  });

  test('scanned QR verification rejects whitespace-only payloads', () async {
    final gateway = _FakeVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.submitScannedQrCode('   '), isFalse);
    expect(gateway.scannedQrCode, isNull);
    expect(controller.errorMessage.value, 'Scan a valid verification QR code.');
  });

  test(
    'QR flow delegates opaque verification material to the SDK boundary',
    () async {
      final gateway = _FakeVerificationGateway();
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startQrVerification(), isTrue);
      final started = controller.session.value!;
      expect(started.method, DeviceVerificationMethod.qr);
      expect(started.qrCodeData, 'MATRIX-VERIFICATION-SECRET');
      expect(started.toString(), isNot(contains('MATRIX-VERIFICATION-SECRET')));
      expect(started.toString(), contains('<redacted>'));

      expect(
        await controller.submitScannedQrCode('SCANNED-OPAQUE-PAYLOAD'),
        isTrue,
      );
      expect(gateway.scannedQrCode, 'SCANNED-OPAQUE-PAYLOAD');
      expect(
        controller.session.value?.stage,
        DeviceVerificationStage.waitingForPeer,
      );

      expect(await controller.confirmQrVerification(), isTrue);
      expect(gateway.confirmedQrTransactionId, 'scanned-transaction');
      expect(controller.session.value?.stage, DeviceVerificationStage.verified);
      expect(controller.trustState.value, CrossSigningTrustState.verified);
      expect(controller.requiresVerification, isFalse);
      expect(gateway.trustReads, 1);
    },
  );

  test(
    'SAS flow exposes only SDK-provided emoji and confirms by transaction',
    () async {
      final gateway = _FakeVerificationGateway();
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startSasVerification(), isTrue);
      expect(controller.session.value?.sasEmoji, const <String>[
        '🐶',
        '🌳',
        '🚲',
      ]);
      expect(controller.session.value.toString(), isNot(contains('🐶')));

      expect(await controller.confirmSasVerification(), isTrue);
      expect(gateway.confirmedSasTransactionId, 'sas-transaction');
      expect(controller.trustState.value, CrossSigningTrustState.verified);
    },
  );

  test('confirmation cannot switch verification transactions', () async {
    final gateway = _FakeVerificationGateway()
      ..returnedQrTransactionId = 'different-transaction';
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.startQrVerification(), isTrue);
    final original = controller.session.value;
    expect(await controller.confirmQrVerification(), isFalse);

    expect(gateway.confirmedQrTransactionId, 'qr-transaction');
    expect(controller.session.value, same(original));
    expect(controller.trustState.value, CrossSigningTrustState.unknown);
    expect(gateway.trustReads, 0);
    expect(
      controller.errorMessage.value,
      'Kite received an invalid verification state.',
    );
  });

  test(
    'verified transaction does not bypass unverified cross-signing trust',
    () async {
      final gateway = _FakeVerificationGateway()
        ..confirmationUpdatesTrust = false;
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startQrVerification(), isTrue);
      final original = controller.session.value;
      expect(await controller.confirmQrVerification(), isFalse);

      expect(controller.session.value, same(original));
      expect(controller.trustState.value, CrossSigningTrustState.unverified);
      expect(controller.requiresVerification, isTrue);
      expect(
        controller.errorMessage.value,
        'Kite could not confirm cross-signing trust for this device.',
      );
    },
  );
  test(
    'method mismatch is rejected before the wrong SDK confirmation',
    () async {
      final gateway = _FakeVerificationGateway();
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startQrVerification(), isTrue);
      expect(await controller.confirmSasVerification(), isFalse);
      expect(gateway.confirmedSasTransactionId, isNull);
      expect(
        controller.errorMessage.value,
        'Start emoji verification before confirming it.',
      );
    },
  );

  test(
    'cancellation keeps a terminal local state without exposing errors',
    () async {
      final gateway = _FakeVerificationGateway();
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startSasVerification(), isTrue);
      expect(await controller.cancelVerification(), isTrue);
      expect(gateway.cancelledTransactionId, 'sas-transaction');
      expect(
        controller.session.value?.stage,
        DeviceVerificationStage.cancelled,
      );

      controller.clearCompletedSession();
      expect(controller.session.value, isNull);
    },
  );

  test('cancelled verification cannot later be confirmed', () async {
    final gateway = _FakeVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.startQrVerification(), isTrue);
    expect(await controller.cancelVerification(), isTrue);
    expect(await controller.confirmQrVerification(), isFalse);

    expect(gateway.confirmedQrTransactionId, isNull);
    expect(controller.trustState.value, CrossSigningTrustState.unknown);
    expect(controller.session.value?.stage, DeviceVerificationStage.cancelled);
  });

  test(
    'gateway failures never expose verification material or secrets',
    () async {
      final gateway = _FakeVerificationGateway()
        ..failure = StateError('access_token=secret recovery_key=also-secret');
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.startQrVerification(), isFalse);
      expect(
        controller.errorMessage.value,
        'Kite could not start QR verification.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
      expect(controller.errorMessage.value, isNot(contains('access_token')));
      expect(controller.errorMessage.value, isNot(contains('recovery_key')));
    },
  );
}
