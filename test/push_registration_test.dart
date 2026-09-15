import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/notifications/push_registration.dart';

final class _FakePushGateway implements PushRegistrationGateway {
  String? registeredAccountId;
  PushProvider? provider;
  String? deviceToken;
  String? unregisteredAccountId;
  String? payloadAccountId;
  String? encryptedPayload;
  Object? failure;

  @override
  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) async {
    if (failure case final error?) throw error;
    payloadAccountId = accountId;
    this.encryptedPayload = encryptedPayload;
    return const DecryptedPushNotification(
      notification: KiteNotification(
        id: 'push-1',
        kind: KiteNotificationKind.message,
        destination: AppDestination.event(
          accountId: 'work',
          roomId: '!room:example.org',
          eventId: r'$event',
        ),
      ),
      content: KiteNotificationContent(
        title: 'Alice',
        body: 'Decrypted message body',
      ),
    );
  }

  @override
  Future<void> register({
    required String accountId,
    required PushProvider provider,
    required String deviceToken,
  }) async {
    if (failure case final error?) throw error;
    registeredAccountId = accountId;
    this.provider = provider;
    this.deviceToken = deviceToken;
  }

  @override
  Future<void> unregister({required String accountId}) async {
    if (failure case final error?) throw error;
    unregisteredAccountId = accountId;
  }
}

void main() {
  test(
    'push token is delegated without being retained in controller state',
    () async {
      final gateway = _FakePushGateway();
      final controller = PushRegistrationController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.register(
          accountId: ' work ',
          provider: PushProvider.fcm,
          deviceToken: 'OPAQUE-PUSH-TOKEN',
        ),
        isTrue,
      );

      expect(gateway.registeredAccountId, 'work');
      expect(gateway.provider, PushProvider.fcm);
      expect(gateway.deviceToken, 'OPAQUE-PUSH-TOKEN');
      expect(controller.registeredAccountIds.value, <String>{'work'});
      expect(controller.toString(), isNot(contains('OPAQUE-PUSH-TOKEN')));

      expect(await controller.unregister('work'), isTrue);
      expect(gateway.unregisteredAccountId, 'work');
      expect(controller.registeredAccountIds.value, isEmpty);
    },
  );

  test('encrypted payload is processed only through SDK boundary', () async {
    final gateway = _FakePushGateway();
    final controller = PushRegistrationController(gateway);
    addTearDown(controller.dispose);

    final notification = await controller.processEncryptedPayload(
      accountId: 'work',
      encryptedPayload: 'ENCRYPTED-PUSH-ENVELOPE',
    );

    expect(gateway.payloadAccountId, 'work');
    expect(gateway.encryptedPayload, 'ENCRYPTED-PUSH-ENVELOPE');
    expect(notification?.notification.id, 'push-1');
    expect(notification?.content.body, 'Decrypted message body');
    expect(notification.toString(), isNot(contains('Decrypted message body')));
    expect(notification.toString(), contains('<redacted>'));
  });

  test('gateway failures never expose tokens or encrypted payloads', () async {
    final gateway = _FakePushGateway()
      ..failure = StateError(
        'token=OPAQUE-PUSH-TOKEN payload=ENCRYPTED-PUSH-ENVELOPE',
      );
    final controller = PushRegistrationController(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.register(
        accountId: 'work',
        provider: PushProvider.fcm,
        deviceToken: 'OPAQUE-PUSH-TOKEN',
      ),
      isFalse,
    );
    expect(
      controller.errorMessage.value,
      'Kite could not register notifications.',
    );
    expect(controller.errorMessage.value, isNot(contains('OPAQUE')));

    expect(
      await controller.processEncryptedPayload(
        accountId: 'work',
        encryptedPayload: 'ENCRYPTED-PUSH-ENVELOPE',
      ),
      isNull,
    );
    expect(
      controller.errorMessage.value,
      'Kite could not process that notification securely.',
    );
    expect(controller.errorMessage.value, isNot(contains('ENCRYPTED')));
  });

  test(
    'invalid registration data is rejected before platform boundary',
    () async {
      final gateway = _FakePushGateway();
      final controller = PushRegistrationController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.register(
          accountId: 'work',
          provider: PushProvider.fcm,
          deviceToken: '',
        ),
        isFalse,
      );
      expect(gateway.registeredAccountId, isNull);

      expect(
        await controller.processEncryptedPayload(
          accountId: 'work',
          encryptedPayload: '',
        ),
        isNull,
      );
      expect(gateway.encryptedPayload, isNull);
    },
  );
}
