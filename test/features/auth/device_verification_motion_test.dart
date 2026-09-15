import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/device_verification_controller.dart';
import 'package:kite/features/auth/device_verification_screen.dart';

final class _DeferredVerificationGateway implements DeviceVerificationGateway {
  final sasStart = Completer<DeviceVerificationSession>();

  @override
  Future<void> cancelVerification(String transactionId) async {}

  @override
  Future<DeviceVerificationSession> confirmQrVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> confirmSasVerification(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<CrossSigningTrustState> loadCrossSigningTrust() async =>
      CrossSigningTrustState.unverified;

  @override
  Future<DeviceVerificationSession> startQrVerification() async =>
      throw UnimplementedError();

  @override
  Future<DeviceVerificationSession> startSasVerification() => sasStart.future;

  @override
  Future<DeviceVerificationSession> submitScannedQrCode(
    String qrCodeData,
  ) async => throw UnimplementedError();
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('verification startup keeps reserved geometry stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredVerificationGateway();
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

    final list = find.byKey(const Key('device-verification-list'));
    final summary = find.byKey(const Key('verification-trust-summary'));
    final actionSlot = find.byKey(const Key('verification-action-slot'));
    final statusSlot = find.byKey(const Key('verification-status-slot'));
    final initialList = _rectOf(tester, list);
    final initialSummary = _rectOf(tester, summary);
    final initialAction = _rectOf(tester, actionSlot);
    final initialStatus = _rectOf(tester, statusSlot);

    await tester.tap(find.byKey(const Key('start-sas-verification')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, summary), initialSummary);
      expect(_rectOf(tester, actionSlot), initialAction);
      expect(_rectOf(tester, statusSlot), initialStatus);
      expect(tester.takeException(), isNull);
    }

    gateway.sasStart.complete(
      DeviceVerificationSession(
        transactionId: 'sas-tx',
        method: DeviceVerificationMethod.sas,
        stage: DeviceVerificationStage.ready,
        sasEmoji: const <String>['🐶', '🌳', '🚲'],
      ),
    );
    await tester.pump();
    expect(_rectOf(tester, actionSlot), initialAction);
    expect(_rectOf(tester, statusSlot), initialStatus);
  });
}
