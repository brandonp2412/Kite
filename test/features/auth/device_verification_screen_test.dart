import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/device_verification_screen.dart';

final class _FakeVerificationGateway implements DeviceVerificationGateway {
  CrossSigningTrustState trust = CrossSigningTrustState.unverified;
  String? scannedPayload;
  int sasStarts = 0;
  int qrStarts = 0;

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
  Future<DeviceVerificationSession> startQrVerification() async {
    qrStarts += 1;
    return DeviceVerificationSession(
      transactionId: 'qr-tx',
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.ready,
      qrCodeData: 'OPAQUE-QR-PAYLOAD',
    );
  }

  @override
  Future<DeviceVerificationSession> startSasVerification() async {
    sasStarts += 1;
    return DeviceVerificationSession(
      transactionId: 'sas-tx',
      method: DeviceVerificationMethod.sas,
      stage: DeviceVerificationStage.ready,
      sasEmoji: const <String>['🐶', '🌳', '🚲'],
    );
  }

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async {
    scannedPayload = qrCodeData;
    return DeviceVerificationSession(
      transactionId: 'scan-tx',
      method: DeviceVerificationMethod.qr,
      stage: DeviceVerificationStage.waitingForPeer,
    );
  }
}

void _useLargeView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('SAS verification presents only SDK emoji and updates trust', (
    tester,
  ) async {
    _useLargeView(tester);
    final gateway = _FakeVerificationGateway();
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

    expect(find.text('Verification required'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-sas-verification')));
    await tester.pump();

    expect(gateway.sasStarts, 1);
    expect(find.text('🐶'), findsOneWidget);
    expect(find.text('🌳'), findsOneWidget);
    expect(find.text('🚲'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-sas-verification')));
    await tester.pump();

    expect(controller.trustState.value, CrossSigningTrustState.verified);
    expect(find.text('Device verified'), findsOneWidget);
    expect(find.text('Verification complete'), findsOneWidget);
  });

  testWidgets(
    'QR presentation receives opaque SDK data without rendering it as text',
    (tester) async {
      _useLargeView(tester);
      final gateway = _FakeVerificationGateway();
      final controller = DeviceVerificationController(gateway);
      addTearDown(controller.dispose);
      await controller.loadTrust();
      String? renderedPayload;

      await tester.pumpWidget(
        MaterialApp(
          home: DeviceVerificationScreen(
            controller: controller,
            loadOnInit: false,
            qrBuilder: (context, payload) {
              renderedPayload = payload;
              return const Placeholder(key: Key('test-qr-renderer'));
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('start-qr-verification')));
      await tester.pump();

      expect(gateway.qrStarts, 1);
      expect(renderedPayload, 'OPAQUE-QR-PAYLOAD');
      expect(find.byKey(const Key('test-qr-renderer')), findsOneWidget);
      expect(find.textContaining('OPAQUE-QR-PAYLOAD'), findsNothing);
    },
  );

  testWidgets('QR scanner payload is passed only to the SDK boundary', (
    tester,
  ) async {
    _useLargeView(tester);
    final gateway = _FakeVerificationGateway();
    final controller = DeviceVerificationController(gateway);
    addTearDown(controller.dispose);
    await controller.loadTrust();

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceVerificationScreen(
          controller: controller,
          loadOnInit: false,
          scanQrCode: () async => 'SCANNED-OPAQUE-PAYLOAD',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('scan-qr-verification')));
    await tester.pump();

    expect(gateway.scannedPayload, 'SCANNED-OPAQUE-PAYLOAD');
    expect(
      controller.session.value?.stage,
      DeviceVerificationStage.waitingForPeer,
    );
    expect(find.textContaining('SCANNED-OPAQUE-PAYLOAD'), findsNothing);
  });
}
