import 'package:signals/signals.dart';

enum DeviceVerificationMethod { qr, sas }

enum DeviceVerificationStage { ready, waitingForPeer, verified, cancelled }

enum CrossSigningTrustState { unknown, unverified, verified }

final class DeviceVerificationSession {
  DeviceVerificationSession({
    required this.transactionId,
    required this.method,
    required this.stage,
    this.qrCodeData,
    List<String> sasEmoji = const <String>[],
  }) : sasEmoji = List<String>.unmodifiable(sasEmoji) {
    if (transactionId.trim().isEmpty) {
      throw ArgumentError.value(transactionId, 'transactionId');
    }
    if (qrCodeData != null && method != DeviceVerificationMethod.qr) {
      throw ArgumentError('QR data can only be attached to QR verification.');
    }
    if (sasEmoji.isNotEmpty && method != DeviceVerificationMethod.sas) {
      throw ArgumentError(
        'SAS emoji can only be attached to SAS verification.',
      );
    }
  }

  final String transactionId;
  final DeviceVerificationMethod method;
  final DeviceVerificationStage stage;

  /// Opaque Matrix SDK-generated QR payload. Keep this transient and never log it.
  final String? qrCodeData;

  /// Matrix SDK-generated SAS presentation. Kite does not derive these values.
  final List<String> sasEmoji;

  bool get isTerminal =>
      stage == DeviceVerificationStage.verified ||
      stage == DeviceVerificationStage.cancelled;

  @override
  String toString() {
    return 'DeviceVerificationSession('
        'transactionId: $transactionId, '
        'method: $method, '
        'stage: $stage, '
        'qrCodeData: ${qrCodeData == null ? 'null' : '<redacted>'}, '
        'sasEmoji: ${sasEmoji.isEmpty ? '[]' : '<redacted>'}'
        ')';
  }
}

abstract interface class DeviceVerificationGateway {
  /// Reads SDK cross-signing trust. No trust decision is made by Kite itself.
  Future<CrossSigningTrustState> loadCrossSigningTrust();

  /// Starts an SDK-owned QR verification transaction.
  Future<DeviceVerificationSession> startQrVerification();

  /// Passes a scanned QR payload back to the SDK for validation.
  Future<DeviceVerificationSession> submitScannedQrCode(String qrCodeData);

  /// Confirms the SDK-validated QR comparison for [transactionId].
  Future<DeviceVerificationSession> confirmQrVerification(String transactionId);

  /// Starts SDK-owned emoji/SAS verification.
  Future<DeviceVerificationSession> startSasVerification();

  /// Confirms the SDK-provided SAS comparison for [transactionId].
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  );

  Future<void> cancelVerification(String transactionId);
}

final class DeviceVerificationController {
  DeviceVerificationController(this._gateway);

  final DeviceVerificationGateway _gateway;

  final trustState = signal(CrossSigningTrustState.unknown);
  final session = signal<DeviceVerificationSession?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  bool get requiresVerification =>
      trustState.value != CrossSigningTrustState.verified;

  Future<void> loadTrust() async {
    if (isBusy.value) return;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      trustState.value = await _gateway.loadCrossSigningTrust();
    } catch (_) {
      errorMessage.value = 'Kite could not read device verification status.';
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> startQrVerification() {
    return _runSessionAction(
      _gateway.startQrVerification,
      expectedMethod: DeviceVerificationMethod.qr,
      failureMessage: 'Kite could not start QR verification.',
    );
  }

  Future<bool> submitScannedQrCode(String qrCodeData) async {
    if (isBusy.value) return false;
    if (qrCodeData.isEmpty) {
      errorMessage.value = 'Scan a valid verification QR code.';
      return false;
    }

    return _runSessionAction(
      () => _gateway.submitScannedQrCode(qrCodeData),
      expectedMethod: DeviceVerificationMethod.qr,
      failureMessage: 'Kite could not verify that QR code.',
    );
  }

  Future<bool> confirmQrVerification() {
    final current = session.value;
    if (current == null || current.method != DeviceVerificationMethod.qr) {
      errorMessage.value = 'Start QR verification before confirming it.';
      return Future<bool>.value(false);
    }
    return _runSessionAction(
      () => _gateway.confirmQrVerification(current.transactionId),
      expectedMethod: DeviceVerificationMethod.qr,
      expectedTransactionId: current.transactionId,
      failureMessage: 'Kite could not confirm QR verification.',
    );
  }

  Future<bool> startSasVerification() {
    return _runSessionAction(
      _gateway.startSasVerification,
      expectedMethod: DeviceVerificationMethod.sas,
      failureMessage: 'Kite could not start emoji verification.',
    );
  }

  Future<bool> confirmSasVerification() {
    final current = session.value;
    if (current == null || current.method != DeviceVerificationMethod.sas) {
      errorMessage.value = 'Start emoji verification before confirming it.';
      return Future<bool>.value(false);
    }
    if (current.sasEmoji.isEmpty) {
      errorMessage.value = 'Wait for the verification emoji before confirming.';
      return Future<bool>.value(false);
    }
    return _runSessionAction(
      () => _gateway.confirmSasVerification(current.transactionId),
      expectedMethod: DeviceVerificationMethod.sas,
      expectedTransactionId: current.transactionId,
      failureMessage: 'Kite could not confirm emoji verification.',
    );
  }

  Future<bool> cancelVerification() async {
    final current = session.value;
    if (current == null || current.isTerminal || isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      await _gateway.cancelVerification(current.transactionId);
      session.value = DeviceVerificationSession(
        transactionId: current.transactionId,
        method: current.method,
        stage: DeviceVerificationStage.cancelled,
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not cancel device verification.';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> _runSessionAction(
    Future<DeviceVerificationSession> Function() action, {
    required DeviceVerificationMethod expectedMethod,
    String? expectedTransactionId,
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (next.method != expectedMethod ||
          (expectedTransactionId != null &&
              next.transactionId != expectedTransactionId)) {
        errorMessage.value = 'Kite received an invalid verification state.';
        return false;
      }
      session.value = next;
      if (next.stage == DeviceVerificationStage.verified) {
        trustState.value = await _gateway.loadCrossSigningTrust();
      }
      return true;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  void clearCompletedSession() {
    final current = session.value;
    if (current?.isTerminal ?? false) session.value = null;
  }

  void dispose() {
    trustState.dispose();
    session.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
