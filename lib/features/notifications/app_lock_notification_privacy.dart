import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/notifications/notification_delivery.dart';

final class AppLockNotificationPrivacy implements NotificationPrivacyPort {
  const AppLockNotificationPrivacy(this._controller);

  final AppLockController _controller;

  @override
  bool get hideNotificationContents =>
      _controller.shouldHideNotificationContents;
}
