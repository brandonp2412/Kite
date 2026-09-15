import 'dart:async';

import 'package:kite/features/calls/incoming_call.dart';

final class IncomingCallSyncUpdate {
  const IncomingCallSyncUpdate.ended(this.callId);

  final String callId;
}

abstract interface class IncomingCallSyncSourcePort {
  Stream<IncomingCallSyncUpdate> get updates;
}

typedef IncomingCallSyncErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

final class IncomingCallSyncBinding {
  IncomingCallSyncBinding({
    required IncomingCallCoordinator incoming,
    required IncomingCallSyncSourcePort source,
    IncomingCallSyncErrorHandler? onError,
  }) : _incoming = incoming,
       _source = source,
       _onError = onError;

  final IncomingCallCoordinator _incoming;
  final IncomingCallSyncSourcePort _source;
  final IncomingCallSyncErrorHandler? _onError;

  StreamSubscription<IncomingCallSyncUpdate>? _subscription;
  Future<void> _pending = Future<void>.value();

  bool get isStarted => _subscription != null;

  void start() {
    if (_subscription != null) return;
    _subscription = _source.updates.listen(
      _enqueue,
      onError: (Object error, StackTrace stackTrace) {
        _onError?.call(error, stackTrace);
      },
    );
  }

  Future<void> flush() => _pending;

  Future<void> stop() async {
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    await subscription.cancel();
    await flush();
  }

  void _enqueue(IncomingCallSyncUpdate update) {
    _pending = _pending.then<void>((_) async {
      try {
        await _incoming.endFromSync(update.callId);
      } catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
      }
    });
  }
}
