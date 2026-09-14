import 'dart:async';

/// Event data already normalised by the Matrix SDK boundary.
///
/// [syncOrder] is an SDK-provided monotonic ordering key within an account.
/// Kite does not attempt to reconstruct Matrix DAG ordering itself.
final class MatrixEventEnvelope {
  const MatrixEventEnvelope({
    required this.eventId,
    required this.roomId,
    required this.syncOrder,
    required this.timestamp,
    required this.senderId,
    required this.summary,
    this.transactionId,
  });

  final String eventId;
  final String roomId;
  final int syncOrder;
  final DateTime timestamp;
  final String senderId;
  final String summary;
  final String? transactionId;
}

/// Deterministically merges incremental sync/back-pagination batches.
///
/// The SDK boundary is responsible for Matrix protocol semantics and supplies
/// [MatrixEventEnvelope.syncOrder]. This reducer only performs presentation
/// deduplication and stable ordering; it never implements Matrix crypto or DAG
/// resolution itself.
abstract final class MatrixEventReducer {
  static List<MatrixEventEnvelope> merge(
    Iterable<MatrixEventEnvelope> existing,
    Iterable<MatrixEventEnvelope> incoming,
  ) {
    final byEventId = <String, MatrixEventEnvelope>{};
    final eventIdByTransactionId = <String, String>{};

    void ingest(MatrixEventEnvelope event) {
      final transactionId = event.transactionId;
      if (transactionId != null) {
        final previousEventId = eventIdByTransactionId[transactionId];
        if (previousEventId != null && previousEventId != event.eventId) {
          byEventId.remove(previousEventId);
        }
        eventIdByTransactionId[transactionId] = event.eventId;
      }

      final previous = byEventId[event.eventId];
      if (previous == null || event.syncOrder >= previous.syncOrder) {
        byEventId[event.eventId] = event;
      }
    }

    for (final event in existing) {
      ingest(event);
    }
    for (final event in incoming) {
      ingest(event);
    }

    final merged = byEventId.values.toList(growable: false)
      ..sort((left, right) {
        final orderComparison = left.syncOrder.compareTo(right.syncOrder);
        if (orderComparison != 0) return orderComparison;

        final timeComparison = left.timestamp.compareTo(right.timestamp);
        if (timeComparison != 0) return timeComparison;

        return left.eventId.compareTo(right.eventId);
      });
    return List<MatrixEventEnvelope>.unmodifiable(merged);
  }
}

final class RoomPresentation {
  const RoomPresentation({
    required this.roomId,
    required this.name,
    this.latestEventId,
  });

  final String roomId;
  final String name;
  final String? latestEventId;

  RoomPresentation copyWith({String? name, String? latestEventId}) {
    return RoomPresentation(
      roomId: roomId,
      name: name ?? this.name,
      latestEventId: latestEventId ?? this.latestEventId,
    );
  }
}

final class PresentationSnapshot {
  const PresentationSnapshot({
    this.rooms = const <RoomPresentation>[],
    this.timelines = const <String, List<MatrixEventEnvelope>>{},
  });

  final List<RoomPresentation> rooms;
  final Map<String, List<MatrixEventEnvelope>> timelines;
}

/// Synchronous presentation cache used by UI-facing state.
///
/// A previously persisted [PresentationSnapshot] can be injected at startup so
/// room/timeline reads are immediate. Applying incremental sync never clears
/// already-known rooms or timelines, which prevents network refreshes from
/// blanking cached screens.
final class MatrixPresentationCache {
  MatrixPresentationCache([
    PresentationSnapshot initial = const PresentationSnapshot(),
  ]) {
    for (final room in initial.rooms) {
      _rooms[room.roomId] = room;
    }
    for (final entry in initial.timelines.entries) {
      _timelines[entry.key] = MatrixEventReducer.merge(
        const <MatrixEventEnvelope>[],
        entry.value,
      );
    }
  }

  final Map<String, RoomPresentation> _rooms = <String, RoomPresentation>{};
  final Map<String, List<MatrixEventEnvelope>> _timelines =
      <String, List<MatrixEventEnvelope>>{};

  List<RoomPresentation> get rooms =>
      List<RoomPresentation>.unmodifiable(_rooms.values);

  RoomPresentation? room(String roomId) => _rooms[roomId];

  List<MatrixEventEnvelope> timeline(String roomId) =>
      _timelines[roomId] ?? const <MatrixEventEnvelope>[];

  void upsertRoom(RoomPresentation room) {
    _rooms[room.roomId] = room;
  }

  void applyEvents(String roomId, Iterable<MatrixEventEnvelope> events) {
    final incoming = events.toList(growable: false);
    if (incoming.isEmpty) return;

    final merged = MatrixEventReducer.merge(timeline(roomId), incoming);
    _timelines[roomId] = merged;

    final existingRoom = _rooms[roomId];
    if (existingRoom != null) {
      _rooms[roomId] = existingRoom.copyWith(
        latestEventId: merged.isEmpty ? null : merged.last.eventId,
      );
    }
  }

  PresentationSnapshot snapshot() {
    return PresentationSnapshot(
      rooms: List<RoomPresentation>.unmodifiable(_rooms.values),
      timelines: Map<String, List<MatrixEventEnvelope>>.unmodifiable(
        <String, List<MatrixEventEnvelope>>{
          for (final entry in _timelines.entries)
            entry.key: List<MatrixEventEnvelope>.unmodifiable(entry.value),
        },
      ),
    );
  }
}

enum OfflineSendState { queued, sending, retryWaiting, sent, failedPermanent }

final class PendingSend {
  const PendingSend({
    required this.transactionId,
    required this.roomId,
    required this.body,
    required this.state,
    required this.attempts,
    this.eventId,
  });

  final String transactionId;
  final String roomId;
  final String body;
  final OfflineSendState state;
  final int attempts;
  final String? eventId;

  PendingSend copyWith({
    OfflineSendState? state,
    int? attempts,
    String? eventId,
  }) {
    return PendingSend(
      transactionId: transactionId,
      roomId: roomId,
      body: body,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      eventId: eventId ?? this.eventId,
    );
  }
}

final class SendAttemptResult {
  const SendAttemptResult._({
    required this.succeeded,
    required this.retryable,
    this.eventId,
  });

  const SendAttemptResult.sent(String eventId)
    : this._(succeeded: true, retryable: false, eventId: eventId);

  const SendAttemptResult.retryableFailure()
    : this._(succeeded: false, retryable: true);

  const SendAttemptResult.permanentFailure()
    : this._(succeeded: false, retryable: false);

  final bool succeeded;
  final bool retryable;
  final String? eventId;
}

typedef MatrixSendOperation = Future<SendAttemptResult> Function(
  PendingSend send,
);

/// Deterministic offline send queue.
///
/// Connectivity only controls whether queued work may drain. Retryable failures
/// enter [OfflineSendState.retryWaiting] and require an explicit [retryNow], so
/// tests and UI state never depend on wall-clock timer races.
final class OfflineSendQueue {
  final Map<String, PendingSend> _sends = <String, PendingSend>{};
  bool _online = true;
  bool _draining = false;

  bool get isOnline => _online;

  List<PendingSend> get sends => List<PendingSend>.unmodifiable(_sends.values);

  void setOnline(bool online) {
    _online = online;
  }

  PendingSend enqueue({
    required String transactionId,
    required String roomId,
    required String body,
  }) {
    final existing = _sends[transactionId];
    if (existing != null) return existing;

    final send = PendingSend(
      transactionId: transactionId,
      roomId: roomId,
      body: body,
      state: OfflineSendState.queued,
      attempts: 0,
    );
    _sends[transactionId] = send;
    return send;
  }

  void retryNow(String transactionId) {
    final send = _sends[transactionId];
    if (send == null || send.state != OfflineSendState.retryWaiting) return;
    _sends[transactionId] = send.copyWith(state: OfflineSendState.queued);
  }

  Future<void> drain(MatrixSendOperation operation) async {
    if (!_online || _draining) return;
    _draining = true;

    try {
      final transactionIds = _sends.keys.toList(growable: false);
      for (final transactionId in transactionIds) {
        if (!_online) break;

        final queued = _sends[transactionId];
        if (queued == null || queued.state != OfflineSendState.queued) {
          continue;
        }

        final sending = queued.copyWith(
          state: OfflineSendState.sending,
          attempts: queued.attempts + 1,
        );
        _sends[transactionId] = sending;

        final result = await operation(sending);
        _sends[transactionId] = sending.copyWith(
          state: result.succeeded
              ? OfflineSendState.sent
              : result.retryable
              ? OfflineSendState.retryWaiting
              : OfflineSendState.failedPermanent,
          eventId: result.eventId,
        );
      }
    } finally {
      _draining = false;
    }
  }
}
