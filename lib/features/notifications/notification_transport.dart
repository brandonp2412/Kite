import 'dart:async';

import 'package:kite/features/notifications/notification_ingress.dart';

abstract interface class NotificationPayloadSourcePort {
  Stream<Map<String, String?>> get payloads;
}

typedef NotificationTransportErrorHandler = void Function(
  NotificationIngressTransport transport,
  Object error,
  StackTrace stackTrace,
);

final class NotificationTransportBinding {
  factory NotificationTransportBinding({
    required NotificationIngressCoordinator ingress,
    NotificationPayloadSourcePort? fcm,
    NotificationPayloadSourcePort? backgroundSync,
    NotificationTransportErrorHandler? onError,
  }) => NotificationTransportBinding._(ingress, fcm, backgroundSync, onError);

  NotificationTransportBinding._(
    this._ingress,
    this._fcm,
    this._backgroundSync,
    this._onError,
  );

  final NotificationIngressCoordinator _ingress;
  final NotificationPayloadSourcePort? _fcm;
  final NotificationPayloadSourcePort? _backgroundSync;
  final NotificationTransportErrorHandler? _onError;

  final List<StreamSubscription<Map<String, String?>>> _subscriptions =
      <StreamSubscription<Map<String, String?>>>[];
  Future<void> _pending = Future<void>.value();
  bool _started = false;

  bool get isStarted => _started;

  void start() {
    if (_started) return;
    _started = true;
    _listen(NotificationIngressTransport.fcm, _fcm);
    _listen(NotificationIngressTransport.backgroundSync, _backgroundSync);
  }

  Future<void> flush() => _pending;

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    final subscriptions = List<StreamSubscription<Map<String, String?>>>.of(
      _subscriptions,
    );
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await flush();
  }

  void _listen(
    NotificationIngressTransport transport,
    NotificationPayloadSourcePort? source,
  ) {
    if (source == null) return;
    _subscriptions.add(
      source.payloads.listen(
        (payload) => _enqueue(transport, payload),
        onError: (Object error, StackTrace stackTrace) {
          _onError?.call(transport, error, stackTrace);
        },
      ),
    );
  }

  void _enqueue(
    NotificationIngressTransport transport,
    Map<String, String?> payload,
  ) {
    final frozenPayload = Map<String, String?>.unmodifiable(payload);
    _pending = _pending.then<void>((_) async {
      try {
        await _ingress.receive(transport: transport, data: frozenPayload);
      } catch (error, stackTrace) {
        _onError?.call(transport, error, stackTrace);
      }
    });
  }
}
