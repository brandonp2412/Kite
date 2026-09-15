import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/app_lock_notification_privacy.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

final class _CredentialGateway implements AppLockCredentialGateway {
  AppLockSettings settings = const AppLockSettings(
    enabled: true,
    biometricsEnabled: false,
    hideNotificationContents: true,
  );

  @override
  Future<void> disable() async {
    settings = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    this.settings = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == '1234';
}

final class _BiometricGateway implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  test(
    'delivery privacy follows app-lock state without retaining message content',
    () async {
      final appLock = AppLockController(
        _CredentialGateway(),
        _BiometricGateway(),
      );
      addTearDown(appLock.dispose);
      await appLock.load();

      final delivery = FakeNotificationDeliveryPort();
      final coordinator = NotificationDeliveryCoordinator(
        privacy: AppLockNotificationPrivacy(appLock),
        delivery: delivery,
      );
      const content = KiteNotificationContent(
        title: 'Alice',
        body: 'Sensitive room message',
      );
      const notification = KiteNotification(
        id: 'message-1',
        kind: KiteNotificationKind.message,
        destination: AppDestination.event(
          accountId: 'work',
          roomId: '!room:example.org',
          eventId: r'$event',
        ),
      );

      await coordinator.upsert(notification: notification, content: content);
      expect(delivery.shown.last.contentsHidden, isTrue);
      expect(
        delivery.shown.last.body,
        NotificationPresentationPolicy.privateBody,
      );

      expect(await appLock.unlockWithPin('1234'), isTrue);
      await coordinator.refreshPrivacy();
      expect(delivery.shown.last.contentsHidden, isFalse);
      expect(delivery.shown.last.body, 'Sensitive room message');

      appLock.lock();
      await coordinator.refreshPrivacy();
      expect(delivery.shown.last.contentsHidden, isTrue);
      expect(
        delivery.shown.last.body,
        NotificationPresentationPolicy.privateBody,
      );
    },
  );
}
