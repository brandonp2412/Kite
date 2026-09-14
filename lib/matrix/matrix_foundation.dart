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

    bool isAtLeastAsFresh(
      MatrixEventEnvelope candidate,
      MatrixEventEnvelope current,
    ) {
      final orderComparison = candidate.syncOrder.compareTo(current.syncOrder);
      if (orderComparison != 0) return orderComparison > 0;

      final timeComparison = candidate.timestamp.compareTo(current.timestamp);
      if (timeComparison != 0) return timeComparison >= 0;

      return candidate.eventId.compareTo(current.eventId) >= 0;
    }

    void ingest(MatrixEventEnvelope event) {
      final previousById = byEventId[event.eventId];
      if (previousById != null && !isAtLeastAsFresh(event, previousById)) {
        return;
      }

      final transactionId = event.transactionId;
      if (transactionId != null) {
        final previousEventId = eventIdByTransactionId[transactionId];
        if (previousEventId != null && previousEventId != event.eventId) {
          final previousByTransaction = byEventId[previousEventId];
          if (previousByTransaction != null &&
              !isAtLeastAsFresh(event, previousByTransaction)) {
            return;
          }
          byEventId.remove(previousEventId);
        }
        eventIdByTransactionId[transactionId] = event.eventId;
      }

      final previousTransactionId = previousById?.transactionId;
      if (previousTransactionId != null &&
          previousTransactionId != transactionId &&
          eventIdByTransactionId[previousTransactionId] == event.eventId) {
        eventIdByTransactionId.remove(previousTransactionId);
      }
      byEventId[event.eventId] = event;
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
    this.backPaginationTokens = const <String, String?>{},
  });

  final List<RoomPresentation> rooms;
  final Map<String, List<MatrixEventEnvelope>> timelines;
  final Map<String, String?> backPaginationTokens;
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
    _backPaginationTokens.addAll(initial.backPaginationTokens);
  }

  final Map<String, RoomPresentation> _rooms = <String, RoomPresentation>{};
  final Map<String, List<MatrixEventEnvelope>> _timelines =
      <String, List<MatrixEventEnvelope>>{};
  final Map<String, String?> _backPaginationTokens = <String, String?>{};

  List<RoomPresentation> get rooms =>
      List<RoomPresentation>.unmodifiable(_rooms.values);

  RoomPresentation? room(String roomId) => _rooms[roomId];

  List<MatrixEventEnvelope> timeline(String roomId) =>
      _timelines[roomId] ?? const <MatrixEventEnvelope>[];

  String? backPaginationToken(String roomId) => _backPaginationTokens[roomId];

  bool hasBackPaginationToken(String roomId) =>
      _backPaginationTokens.containsKey(roomId);

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

  void applyIncrementalSync(IncrementalSyncBatch batch) {
    for (final room in batch.rooms) {
      upsertRoom(room);
    }
    for (final entry in batch.eventsByRoom.entries) {
      applyEvents(entry.key, entry.value);
    }
  }

  void applyBackPaginationPage(String roomId, BackPaginationPage page) {
    _backPaginationTokens[roomId] = page.previousToken;
    if (page.events.isEmpty) return;
    _timelines[roomId] = MatrixEventReducer.merge(
      timeline(roomId),
      page.events,
    );
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
      backPaginationTokens: Map<String, String?>.unmodifiable(
        _backPaginationTokens,
      ),
    );
  }
}

final class BackPaginationPage {
  const BackPaginationPage({required this.events, required this.previousToken});

  final List<MatrixEventEnvelope> events;
  final String? previousToken;
}

typedef BackPaginationLoader = Future<BackPaginationPage> Function(
  String roomId,
  String token,
);

/// Requests older timeline pages when the viewport approaches the leading edge.
///
/// The controller is intentionally UI-framework agnostic: widgets report their
/// first visible index and the controller performs at most one request at a
/// time. Loaded events merge into the existing cache, so visible timeline data
/// is never cleared while a page is fetched.
final class TimelineBackPaginationController {
  TimelineBackPaginationController({
    required this.cache,
    required this.loadPage,
    this.prefetchThreshold = 8,
  });

  final MatrixPresentationCache cache;
  final BackPaginationLoader loadPage;
  final int prefetchThreshold;
  final Set<String> _roomsLoading = <String>{};

  bool isLoading(String roomId) => _roomsLoading.contains(roomId);

  Future<bool> onViewport({
    required String roomId,
    required int firstVisibleIndex,
  }) async {
    if (firstVisibleIndex > prefetchThreshold || isLoading(roomId)) {
      return false;
    }

    if (!cache.hasBackPaginationToken(roomId)) return false;
    final token = cache.backPaginationToken(roomId);
    if (token == null || token.isEmpty) return false;

    _roomsLoading.add(roomId);
    try {
      final page = await loadPage(roomId, token);
      cache.applyBackPaginationPage(roomId, page);
      return true;
    } finally {
      _roomsLoading.remove(roomId);
    }
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
  OfflineSendQueue([Iterable<PendingSend> restored = const <PendingSend>[]]) {
    for (final send in restored) {
      _sends[send.transactionId] = send.state == OfflineSendState.sending
          ? send.copyWith(state: OfflineSendState.queued)
          : send;
    }
  }

  final Map<String, PendingSend> _sends = <String, PendingSend>{};
  bool _online = true;
  bool _draining = false;

  bool get isOnline => _online;

  List<PendingSend> get sends => List<PendingSend>.unmodifiable(_sends.values);

  List<PendingSend> snapshot() => List<PendingSend>.unmodifiable(_sends.values);

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

        SendAttemptResult result;
        try {
          result = await operation(sending);
        } on Exception {
          _sends[transactionId] = sending.copyWith(
            state: OfflineSendState.retryWaiting,
          );
          continue;
        }
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

final class IncrementalSyncBatch {
  const IncrementalSyncBatch({
    this.rooms = const <RoomPresentation>[],
    this.eventsByRoom = const <String, List<MatrixEventEnvelope>>{},
  });

  final List<RoomPresentation> rooms;
  final Map<String, List<MatrixEventEnvelope>> eventsByRoom;
}

typedef IncrementalSyncLoader = Future<IncrementalSyncBatch> Function();

/// Coordinates connectivity recovery without replacing presentation state.
///
/// Going offline only pauses sends. On recovery, an incremental SDK-provided
/// batch is loaded and merged into the existing presentation cache, then queued
/// sends drain. If connectivity drops while a recovery request is in flight,
/// that stale result is ignored so an obsolete response cannot move visible
/// room/timeline state after the app is offline again.
final class MatrixConnectivityCoordinator {
  MatrixConnectivityCoordinator({
    required this.cache,
    required this.sendQueue,
    required this.loadRecoveryBatch,
    required this.sendOperation,
  });

  final MatrixPresentationCache cache;
  final OfflineSendQueue sendQueue;
  final IncrementalSyncLoader loadRecoveryBatch;
  final MatrixSendOperation sendOperation;

  bool _online = true;
  Future<bool>? _activeRecovery;

  bool get isOnline => _online;
  bool get isRecovering => _activeRecovery != null;

  Future<bool> setOnline(bool online) async {
    final changed = online != _online;
    _online = online;
    sendQueue.setOnline(online);

    if (!online) return changed;

    final active = _activeRecovery;
    if (!changed && active != null) {
      await active;
      return false;
    }
    if (!changed) return false;

    final recovery = _recover();
    _activeRecovery = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_activeRecovery, recovery)) {
        _activeRecovery = null;
      }
    }
    return true;
  }

  Future<bool> _recover() async {
    final batch = await loadRecoveryBatch();
    if (!_online) return false;

    cache.applyIncrementalSync(batch);
    await sendQueue.drain(sendOperation);
    return true;
  }
}
