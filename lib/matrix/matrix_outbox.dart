import 'dart:async';
import 'dart:collection';

import 'package:kite/matrix/matrix_runtime_coordinator.dart';

enum MatrixOutboxState {
  queuedOffline,
  sending,
  retryScheduled,
  failedPermanent,
  sent,
}

final class MatrixOutboxItem {
  MatrixOutboxItem({
    required this.localId,
    required this.roomId,
    required this.transactionId,
    required this.eventType,
    required Map<String, Object?> content,
    required this.state,
    this.attempt = 0,
    this.nextRetryAt,
    this.failureCode,
    this.eventId,
  }) : content = UnmodifiableMapView<String, Object?>(content);

  final String localId;
  final String roomId;
  final String transactionId;
  final String eventType;
  final Map<String, Object?> content;
  final MatrixOutboxState state;
  final int attempt;
  final DateTime? nextRetryAt;
  final String? failureCode;
  final String? eventId;

  MatrixOutboxItem copyWith({
    MatrixOutboxState? state,
    int? attempt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    String? failureCode,
    bool clearFailureCode = false,
    String? eventId,
    bool clearEventId = false,
  }) {
    return MatrixOutboxItem(
      localId: localId,
      roomId: roomId,
      transactionId: transactionId,
      eventType: eventType,
      content: content,
      state: state ?? this.state,
      attempt: attempt ?? this.attempt,
      nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
      failureCode: clearFailureCode ? null : failureCode ?? this.failureCode,
      eventId: clearEventId ? null : eventId ?? this.eventId,
    );
  }
}

final class MatrixSendReceipt {
  const MatrixSendReceipt({required this.eventId});

  final String eventId;
}

final class MatrixSendFailure implements Exception {
  const MatrixSendFailure({required this.code, required this.retryable});

  final String code;
  final bool retryable;
}

abstract interface class MatrixSendTransport {
  Future<MatrixSendReceipt> send(MatrixOutboxItem item);
}

abstract interface class MatrixEncryptedOutboxStore {
  bool get isEncryptedAtRest;

  Future<List<MatrixOutboxItem>> loadPending();

  Future<void> replacePending(List<MatrixOutboxItem> items);
}

typedef MatrixRetryDelay = Duration Function(int attempt);

final class MatrixOutbox {
  MatrixOutbox({
    required MatrixEncryptedOutboxStore store,
    required this.transport,
    required MatrixNetworkState initialNetworkState,
    MatrixRetryDelay? retryDelay,
  }) : _store = store,
       _networkState = initialNetworkState,
       _retryDelay = retryDelay ?? _defaultRetryDelay {
    if (!store.isEncryptedAtRest) {
      throw StateError('Matrix outbox persistence must be encrypted at rest');
    }
  }

  final MatrixEncryptedOutboxStore _store;
  final MatrixSendTransport transport;
  final MatrixRetryDelay _retryDelay;
  final StreamController<MatrixOutboxItem> _transitions =
      StreamController<MatrixOutboxItem>.broadcast(sync: true);
  final List<MatrixOutboxItem> _pending = <MatrixOutboxItem>[];

  MatrixNetworkState _networkState;
  bool _hydrated = false;
  bool _closed = false;
  Future<void> _transition = Future<void>.value();

  Stream<MatrixOutboxItem> get transitions => _transitions.stream;

  List<MatrixOutboxItem> get pending =>
      List<MatrixOutboxItem>.unmodifiable(_pending);

  Future<void> hydrate({required DateTime now}) {
    _ensureOpen();
    return _enqueueTransition(() async {
      if (_hydrated) return;
      final stored = await _store.loadPending();
      _pending
        ..clear()
        ..addAll(
          stored.map(
            (item) => item.state == MatrixOutboxState.sending
                ? item.copyWith(
                    state: MatrixOutboxState.queuedOffline,
                    clearNextRetryAt: true,
                    clearFailureCode: true,
                  )
                : item,
          ),
        );
      _hydrated = true;
      await _persist();
      if (_networkState == MatrixNetworkState.online) {
        await _flushEligible(now);
      }
    });
  }

  Future<void> enqueue(MatrixOutboxItem item, {required DateTime now}) {
    _ensureOpen();
    return _enqueueTransition(() async {
      _requireHydrated();
      if (_pending.any((pending) => pending.localId == item.localId)) {
        throw StateError('Duplicate Matrix outbox localId ${item.localId}');
      }
      if (_pending.any(
        (pending) => pending.transactionId == item.transactionId,
      )) {
        throw StateError(
          'Duplicate Matrix outbox transactionId ${item.transactionId}',
        );
      }

      final queued = item.copyWith(
        state: MatrixOutboxState.queuedOffline,
        clearNextRetryAt: true,
        clearFailureCode: true,
        clearEventId: true,
      );
      _pending.add(queued);
      await _persist();
      _transitions.add(queued);
      if (_networkState == MatrixNetworkState.online) {
        await _flushEligible(now);
      }
    });
  }

  Future<void> updateNetworkState(
    MatrixNetworkState state, {
    required DateTime now,
  }) {
    _ensureOpen();
    return _enqueueTransition(() async {
      _requireHydrated();
      _networkState = state;
      if (state == MatrixNetworkState.online) {
        await _flushEligible(now);
      }
    });
  }

  Future<void> retryDue(DateTime now) {
    _ensureOpen();
    return _enqueueTransition(() async {
      _requireHydrated();
      if (_networkState == MatrixNetworkState.online) {
        await _flushEligible(now);
      }
    });
  }

  Future<void> retry(String localId, {required DateTime now}) {
    _ensureOpen();
    return _enqueueTransition(() async {
      _requireHydrated();
      final index = _pending.indexWhere((item) => item.localId == localId);
      if (index < 0) return;
      final item = _pending[index];
      if (item.state == MatrixOutboxState.sending) return;

      final queued = item.copyWith(
        state: MatrixOutboxState.queuedOffline,
        clearNextRetryAt: true,
        clearFailureCode: true,
        clearEventId: true,
      );
      _pending[index] = queued;
      await _persist();
      _transitions.add(queued);
      if (_networkState == MatrixNetworkState.online) {
        await _flushEligible(now);
      }
    });
  }

  Future<void> close() {
    if (_closed) return _transition;
    _closed = true;
    final closing = _transition.then<void>(
      (_) => _transitions.close(),
      onError: (Object _, StackTrace _) => _transitions.close(),
    );
    _transition = closing.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return closing;
  }

  Future<void> _flushEligible(DateTime now) async {
    if (_networkState != MatrixNetworkState.online) return;

    for (var index = 0; index < _pending.length;) {
      final item = _pending[index];
      if (!_isEligible(item, now)) {
        index += 1;
        continue;
      }

      final sending = item.copyWith(
        state: MatrixOutboxState.sending,
        attempt: item.attempt + 1,
        clearNextRetryAt: true,
        clearFailureCode: true,
      );
      _pending[index] = sending;
      await _persist();
      _transitions.add(sending);

      try {
        final receipt = await transport.send(sending);
        final sent = sending.copyWith(
          state: MatrixOutboxState.sent,
          eventId: receipt.eventId,
          clearFailureCode: true,
          clearNextRetryAt: true,
        );
        _pending.removeAt(index);
        await _persist();
        _transitions.add(sent);
      } on MatrixSendFailure catch (failure) {
        if (!failure.retryable) {
          final failed = sending.copyWith(
            state: MatrixOutboxState.failedPermanent,
            failureCode: failure.code,
          );
          _pending[index] = failed;
          await _persist();
          _transitions.add(failed);
          index += 1;
          continue;
        }

        await _scheduleRetry(index, sending, now, failure.code);
        index += 1;
      } catch (_) {
        await _scheduleRetry(index, sending, now, 'transport_error');
        index += 1;
      }
    }
  }

  Future<void> _scheduleRetry(
    int index,
    MatrixOutboxItem sending,
    DateTime now,
    String failureCode,
  ) async {
    final retry = sending.copyWith(
      state: MatrixOutboxState.retryScheduled,
      nextRetryAt: now.add(_retryDelay(sending.attempt)),
      failureCode: failureCode,
    );
    _pending[index] = retry;
    await _persist();
    _transitions.add(retry);
  }

  static bool _isEligible(MatrixOutboxItem item, DateTime now) {
    return switch (item.state) {
      MatrixOutboxState.queuedOffline => true,
      MatrixOutboxState.retryScheduled =>
        item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now),
      MatrixOutboxState.sending ||
      MatrixOutboxState.failedPermanent ||
      MatrixOutboxState.sent => false,
    };
  }

  Future<void> _persist() {
    return _store.replacePending(List<MatrixOutboxItem>.unmodifiable(_pending));
  }

  void _requireHydrated() {
    if (!_hydrated) {
      throw StateError('Matrix outbox must be hydrated before use');
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Matrix outbox is closed');
    }
  }

  Future<void> _enqueueTransition(Future<void> Function() action) {
    final next = _transition.then<void>(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static Duration _defaultRetryDelay(int attempt) {
    final exponent = attempt.clamp(1, 6) - 1;
    return Duration(seconds: 1 << exponent);
  }
}
