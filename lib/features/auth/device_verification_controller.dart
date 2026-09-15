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
    final normalizedTransactionId = transactionId.trim();
    if (normalizedTransactionId.isEmpty ||
        normalizedTransactionId != transactionId ||
        transactionId.contains(RegExp(r'\s'))) {
      throw ArgumentError('Verification transaction ID is invalid.');
    }
    if (qrCodeData != null && method != DeviceVerificationMethod.qr) {
      throw ArgumentError('QR data can only be attached to QR verification.');
    }
    if (qrCodeData != null && qrCodeData!.trim().isEmpty) {
      throw ArgumentError('Verification QR data cannot be empty.');
    }
    if (sasEmoji.isNotEmpty && method != DeviceVerificationMethod.sas) {
      throw ArgumentError(
        'SAS emoji can only be attached to SAS verification.',
      );
    }
    if (sasEmoji.any((emoji) => emoji.trim().isEmpty)) {
      throw ArgumentError('Verification emoji cannot be empty.');
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
  int _accountGeneration = 0;

  final trustState = signal(CrossSigningTrustState.unknown);
  final session = signal<DeviceVerificationSession?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  bool get requiresVerification =>
      trustState.value != CrossSigningTrustState.verified;

  bool resetForAccountChange() {
    _accountGeneration += 1;
    trustState.value = CrossSigningTrustState.unknown;
    session.value = null;
    isBusy.value = false;
    errorMessage.value = null;
    return true;
  }

  Future<void> loadTrust() async {
    if (isBusy.value) return;
    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final trust = await _gateway.loadCrossSigningTrust();
      if (generation != _accountGeneration) return;
      trustState.value = trust;
    } catch (_) {
      if (generation == _accountGeneration) {
        trustState.value = CrossSigningTrustState.unknown;
        errorMessage.value = 'Kite could not read device verification status.';
      }
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
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
    if (qrCodeData.trim().isEmpty) {
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
    if (current == null ||
        current.method != DeviceVerificationMethod.qr ||
        current.isTerminal) {
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
    if (current == null ||
        current.method != DeviceVerificationMethod.sas ||
        current.isTerminal) {
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

    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      await _gateway.cancelVerification(current.transactionId);
      if (generation != _accountGeneration) return false;
      session.value = DeviceVerificationSession(
        transactionId: current.transactionId,
        method: current.method,
        stage: DeviceVerificationStage.cancelled,
      );
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = 'Kite could not cancel device verification.';
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
    }
  }

  Future<bool> _runSessionAction(
    Future<DeviceVerificationSession> Function() action, {
    required DeviceVerificationMethod expectedMethod,
    String? expectedTransactionId,
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (generation != _accountGeneration) return false;
      if (next.method != expectedMethod ||
          (expectedTransactionId != null &&
              next.transactionId != expectedTransactionId)) {
        errorMessage.value = 'Kite received an invalid verification state.';
        return false;
      }
      if (next.stage == DeviceVerificationStage.verified) {
        final trust = await _gateway.loadCrossSigningTrust();
        if (generation != _accountGeneration) return false;
        trustState.value = trust;
        if (trust != CrossSigningTrustState.verified) {
          errorMessage.value =
              'Kite could not confirm cross-signing trust for this device.';
          return false;
        }
      }
      session.value = next;
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = failureMessage;
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
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
