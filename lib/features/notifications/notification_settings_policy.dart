import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/features/settings/settings_controller.dart';

abstract interface class NotificationPreferencesSourcePort {
  NotificationPreferences get notificationPreferences;
}

final class SettingsControllerNotificationPreferencesSource
    implements NotificationPreferencesSourcePort {
  const SettingsControllerNotificationPreferencesSource(this.controller);

  final SettingsController controller;

  @override
  NotificationPreferences get notificationPreferences =>
      controller.settings.value.notifications;
}

final class SettingsNotificationDispatchPolicy
    implements NotificationDispatchPolicyPort {
  const SettingsNotificationDispatchPolicy(this._preferences);

  final NotificationPreferencesSourcePort _preferences;

  @override
  bool allows({
    required MatrixNotificationEvent event,
    required KiteNotification notification,
  }) {
    final preferences = _preferences.notificationPreferences;
    if (!preferences.masterEnabled) return false;

    return switch (event.kind) {
      MatrixNotificationEventKind.invite => true,
      MatrixNotificationEventKind.call => preferences.isEnabled(
        NotificationCategory.calls,
      ),
      MatrixNotificationEventKind.message ||
      MatrixNotificationEventKind.mention ||
      MatrixNotificationEventKind.thread => _allowsRoomEvent(
        event,
        preferences,
      ),
    };
  }

  bool _allowsRoomEvent(
    MatrixNotificationEvent event,
    NotificationPreferences preferences,
  ) {
    return switch (preferences.roomMode(event.roomId)) {
      RoomNotificationMode.mute => false,
      RoomNotificationMode.allMessages => true,
      RoomNotificationMode.mentionsOnly =>
        event.kind == MatrixNotificationEventKind.mention,
      RoomNotificationMode.inherit => switch (event.kind) {
        MatrixNotificationEventKind.message ||
        MatrixNotificationEventKind.thread => preferences.isEnabled(
          NotificationCategory.messages,
        ),
        MatrixNotificationEventKind.mention => preferences.isEnabled(
          NotificationCategory.mentions,
        ),
        MatrixNotificationEventKind.invite ||
        MatrixNotificationEventKind.call => false,
      },
    };
  }
}
