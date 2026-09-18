import 'package:kite/core/async_controller_lifecycle.dart';
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

final class PushRegistrationController with AsyncControllerLifecycle {
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
    if (controllerDisposed) return false;
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || deviceToken.trim().isEmpty) {
      errorMessage.value = 'Kite could not register notifications.';
      return false;
    }
    if (!_begin(normalizedAccountId)) return false;

    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    try {
      await _gateway.register(
        accountId: normalizedAccountId,
        provider: provider,
        deviceToken: deviceToken,
      );
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      registeredAccountIds.value = Set<String>.unmodifiable(<String>{
        ...registeredAccountIds.value,
        normalizedAccountId,
      });
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not register notifications.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        _end(normalizedAccountId);
      }
    }
  }

  Future<bool> unregister(String accountId) async {
    if (controllerDisposed) return false;
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || !_begin(normalizedAccountId)) {
      return false;
    }

    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    try {
      await _gateway.unregister(accountId: normalizedAccountId);
      if (!isControllerLifecycleCurrent(lifecycle)) return false;
      final next = <String>{...registeredAccountIds.value}
        ..remove(normalizedAccountId);
      registeredAccountIds.value = Set<String>.unmodifiable(next);
      return true;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value = 'Kite could not unregister notifications.';
      }
      return false;
    } finally {
      if (isControllerLifecycleCurrent(lifecycle)) {
        _end(normalizedAccountId);
      }
    }
  }

  Future<DecryptedPushNotification?> processEncryptedPayload({
    required String accountId,
    required String encryptedPayload,
  }) async {
    if (controllerDisposed) return null;
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty || encryptedPayload.trim().isEmpty) {
      errorMessage.value = 'Kite received an invalid notification.';
      return null;
    }

    final lifecycle = captureControllerLifecycle();
    errorMessage.value = null;
    try {
      final decoded = await _gateway.processEncryptedPayload(
        accountId: normalizedAccountId,
        encryptedPayload: encryptedPayload,
      );
      if (!isControllerLifecycleCurrent(lifecycle)) return null;
      if (decoded == null) return null;
      if (decoded.notification.destination.accountId != normalizedAccountId) {
        errorMessage.value = 'Kite received an invalid notification.';
        return null;
      }
      return decoded;
    } catch (_) {
      if (isControllerLifecycleCurrent(lifecycle)) {
        errorMessage.value =
            'Kite could not process that notification securely.';
      }
      return null;
    }
  }

  bool _begin(String accountId) {
    if (controllerDisposed || busyAccountIds.value.contains(accountId)) {
      return false;
    }
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
    if (!disposeControllerLifecycle()) return;
    registeredAccountIds.dispose();
    busyAccountIds.dispose();
    errorMessage.dispose();
  }
}
