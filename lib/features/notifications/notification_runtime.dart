import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_resolution.dart';
import 'package:kite/features/notifications/notification_transport.dart';

final class NotificationRuntime {
  factory NotificationRuntime({
    required NotificationIngressAccountPort accounts,
    required NotificationEventResolverPort resolver,
    required NotificationDispatchCoordinator dispatch,
    NotificationPayloadSourcePort? fcm,
    NotificationPayloadSourcePort? backgroundSync,
    NotificationTransportErrorHandler? onError,
  }) {
    final resolution = NotificationResolutionCoordinator(
      resolver: resolver,
      dispatch: dispatch,
    );
    final ingress = NotificationIngressCoordinator(
      accounts: accounts,
      onAccepted: resolution.handleAccepted,
    );
    return NotificationRuntime._(
      NotificationTransportBinding(
        ingress: ingress,
        fcm: fcm,
        backgroundSync: backgroundSync,
        onError: onError,
      ),
    );
  }

  const NotificationRuntime._(this._transport);

  final NotificationTransportBinding _transport;

  bool get isStarted => _transport.isStarted;

  void start() => _transport.start();

  Future<void> flush() => _transport.flush();

  Future<void> stop() => _transport.stop();
}
