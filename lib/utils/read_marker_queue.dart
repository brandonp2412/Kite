// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

typedef ReadMarkerSender = Future<void> Function(String? eventId);
typedef ReadMarkerErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Serializes read-marker writes while coalescing overlapping requests to the
/// latest requested target.
///
/// A null [eventId] is meaningful: it asks the caller to resolve the latest
/// readable event when the queued request actually runs.
class ReadMarkerQueue {
  ReadMarkerQueue({
    required ReadMarkerSender send,
    required ReadMarkerErrorHandler onError,
  }) : _send = send,
       _onError = onError;

  final ReadMarkerSender _send;
  final ReadMarkerErrorHandler _onError;

  bool _running = false;
  bool _hasPending = false;
  String? _pendingEventId;

  void request(String? eventId) {
    if (_running) {
      _hasPending = true;
      _pendingEventId = eventId;
      return;
    }

    _running = true;
    unawaited(_drain(eventId));
  }

  Future<void> _drain(String? eventId) async {
    var nextEventId = eventId;

    while (true) {
      try {
        await _send(nextEventId);
      } catch (error, stackTrace) {
        _onError(error, stackTrace);
      }

      if (!_hasPending) {
        _running = false;
        return;
      }

      nextEventId = _pendingEventId;
      _hasPending = false;
      _pendingEventId = null;
    }
  }
}
