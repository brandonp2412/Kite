import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';
import 'package:kite/features/auth/room_encryption_settings_screen.dart';

final class _FakeTrustGateway implements EncryptionTrustGateway {
  RoomEncryptionTrust current = RoomEncryptionTrust(
    roomId: '!room:example.org',
    isEncrypted: true,
    trustState: EncryptionTrustState.unverifiedDevice,
    historySharingSupported: true,
    historySharingEnabled: false,
  );
  bool? historySharing;

  @override
  Future<RoomEncryptionTrust> loadRoomTrust(String roomId) async => current;

  @override
  Future<RoomEncryptionTrust> setHistorySharing({
    required String roomId,
    required bool enabled,
  }) async {
    historySharing = enabled;
    current = current.copyWith(historySharingEnabled: enabled);
    return current;
  }
}

void main() {
  testWidgets('shows unverified-device warning and delegates history sharing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final gateway = _FakeTrustGateway();
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

    expect(
      find.text('This encrypted room includes an unverified device.'),
      findsOneWidget,
    );
    expect(
      find.text('Messages use Matrix end-to-end encryption.'),
      findsOneWidget,
    );
    final sharing = find.byKey(const Key('encrypted-history-sharing'));
    expect(tester.widget<SwitchListTile>(sharing).value, isFalse);

    await tester.tap(sharing);
    await tester.pump();

    expect(gateway.historySharing, isTrue);
    expect(controller.state.value?.historySharingEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(sharing).value, isTrue);
  });

  testWidgets(
    'verified and unencrypted states have distinct trust indicators',
    (tester) async {
      final gateway = _FakeTrustGateway()
        ..current = RoomEncryptionTrust(
          roomId: '!room:example.org',
          isEncrypted: true,
          trustState: EncryptionTrustState.verified,
          historySharingSupported: false,
          historySharingEnabled: false,
        );
      final controller = EncryptionTrustController(gateway);
      addTearDown(controller.dispose);
      await controller.load('!room:example.org');

      await tester.pumpWidget(
        MaterialApp(home: RoomEncryptionTrustBanner(controller: controller)),
      );
      expect(find.text('Encrypted · verified devices'), findsOneWidget);

      gateway.current = RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: false,
        trustState: EncryptionTrustState.unknown,
        historySharingSupported: false,
        historySharingEnabled: false,
      );
      await controller.load('!room:example.org');
      await tester.pump();

      expect(find.text('This room is not encrypted.'), findsOneWidget);
    },
  );
}
