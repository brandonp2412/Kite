import 'package:kite/features/notifications/notification_routing.dart';
import 'package:signals/signals.dart';

enum PushProvider { fcm, apns, unifiedPush }

final class DecryptedPushNotification {
  const DecryptedPushNotification({
    required this.notification,
    required this.content,
  });

  final KiteNotification notification;
  final KiteNotificationContent content;

  @override
  String toString() =>
      'DecryptedPushNotification(notificationId: ${notification.id}, content: <redacted>)';
}

abstract interface class PushRegistrationGateway {
  /// Registers an opaque platform push token for one isolated Matrix account.
  /// Implementations must keep the token inside the platform/SDK boundary.
  Future<void> register({
    required String accountId,
    required PushProvider provider,
    required String deviceToken,
  });

  Future<void> unregister({required String accountId});

  /// Delegates decryption and Matrix push-rule interpretation to the audited
  /// SDK boundary. Flutter receives only the notification data it must present.
  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  });
}

final class PushRegistrationController {
  PushRegistrationController(this._gateway);

  final PushRegistrationGateway _gateway;

  final registeredAccountIds = signal<Set<String>>(const <String>{});
  final busyAccountIds = signal<Set<String>>(const <String>{});
  final errorMessage = signal<String?>(null);

  bool isRegistered(String accountId) =>
      registeredAccountIds.value.contains(accountId);

  Future<bool> register({
    required String accountId,
    required PushProvider provider,
    required String deviceToken,
  }) async {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || deviceToken.isEmpty) {
      errorMessage.value = 'Kite could not register notifications.';
      return false;
    }
    if (!_begin(normalizedAccountId)) return false;

    errorMessage.value = null;
    try {
      await _gateway.register(
        accountId: normalizedAccountId,
        provider: provider,
        deviceToken: deviceToken,
      );
      registeredAccountIds.value = Set<String>.unmodifiable(<String>{
        ...registeredAccountIds.value,
        normalizedAccountId,
      });
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not register notifications.';
      return false;
    } finally {
      _end(normalizedAccountId);
    }
  }

  Future<bool> unregister(String accountId) async {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || !_begin(normalizedAccountId)) {
      return false;
    }

    errorMessage.value = null;
    try {
      await _gateway.unregister(accountId: normalizedAccountId);
      final next = <String>{...registeredAccountIds.value}
        ..remove(normalizedAccountId);
      registeredAccountIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not unregister notifications.';
      return false;
    } finally {
      _end(normalizedAccountId);
    }
  }

  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) async {
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || encryptedPayload.isEmpty) {
      errorMessage.value = 'Kite received an invalid notification.';
      return null;
    }

    errorMessage.value = null;
    try {
      return await _gateway.processEncryptedPayload(
        accountId: normalizedAccountId,
        encryptedPayload: encryptedPayload,
      );
    } catch (_) {
      errorMessage.value = 'Kite could not process that notification securely.';
      return null;
    }
  }

  bool _begin(String accountId) {
    if (busyAccountIds.value.contains(accountId)) return false;
    busyAccountIds.value = Set<String>.unmodifiable(<String>{
      ...busyAccountIds.value,
      accountId,
    });
    return true;
  }

  void _end(String accountId) {
    final next = <String>{...busyAccountIds.value}..remove(accountId);
    busyAccountIds.value = Set<String>.unmodifiable(next);
  }

  void dispose() {
    registeredAccountIds.dispose();
    busyAccountIds.dispose();
    errorMessage.dispose();
  }
}
