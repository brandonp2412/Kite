import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/room_encryption_settings_screen.dart';

final class _DeferredTrustGateway implements EncryptionTrustGateway {
  final update = Completer<RoomEncryptionTrust>();

  static final initial = RoomEncryptionTrust(
    roomId: '!room:example.org',
    isEncrypted: true,
    trustState: EncryptionTrustState.unverifiedDevice,
    historySharingSupported: true,
    historySharingEnabled: false,
  );

  @override
  Future<RoomEncryptionTrust> loadRoomTrust(String roomId) async => initial;

  @override
  Future<RoomEncryptionTrust> setHistorySharing({
    required String roomId,
    required bool enabled,
  }) => update.future;
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets(
    'history-sharing mutation keeps encryption geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final gateway = _DeferredTrustGateway();
      final controller = EncryptionTrustController(gateway);
      addTearDown(controller.dispose);
      await controller.load('!room:example.org');

      await tester.pumpWidget(
        MaterialApp(
          home: RoomEncryptionSettingsScreen(
            roomId: '!room:example.org',
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );

      final list = find.byKey(const Key('room-encryption-settings-list'));
      final banner = find.byKey(const Key('room-encryption-trust-banner'));
      final loading = find.byKey(const Key('room-encryption-loading-slot'));
      final status = find.byKey(const Key('room-encryption-status-slot'));
      final initialList = _rectOf(tester, list);
      final initialBanner = _rectOf(tester, banner);
      final initialLoading = _rectOf(tester, loading);
      final initialStatus = _rectOf(tester, status);

      await tester.tap(find.byKey(const Key('encrypted-history-sharing')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, banner), initialBanner);
        expect(_rectOf(tester, loading), initialLoading);
        expect(_rectOf(tester, status), initialStatus);
        expect(tester.takeException(), isNull);
      }

      gateway.update.complete(
        _DeferredTrustGateway.initial.copyWith(historySharingEnabled: true),
      );
      await tester.pump();
      expect(_rectOf(tester, banner), initialBanner);
      expect(_rectOf(tester, status), initialStatus);
    },
  );
}
