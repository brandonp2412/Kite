import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals.dart';

abstract interface class ThreadSendPort {
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  });
}

class DeterministicThreadSendPort implements ThreadSendPort {
  const DeterministicThreadSendPort({
    this.latency = const Duration(milliseconds: 140),
  });

  final Duration latency;

  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) async {
    await Future<void>.delayed(latency);
    return TimelineSendOutcome.sent;
  }
}

@immutable
class ThreadReply {
  ThreadReply({
    required this.id,
    required this.sender,
    required this.body,
    required this.mine,
    required this.timeLabel,
    TimelineSendState sendState = TimelineSendState.sent,
  }) : sendState = signal(sendState);

  final String id;
  final String sender;
  final String body;
  final bool mine;
  final String timeLabel;
  final Signal<TimelineSendState> sendState;
}

class ThreadController {
  ThreadController({ThreadSendPort? sendPort})
    : _sendPort = sendPort ?? const DeterministicThreadSendPort();

  ThreadSendPort _sendPort;
  final Map<String, Signal<List<ThreadReply>>> _threads =
      <String, Signal<List<ThreadReply>>>{};
  int _transactionCounter = 0;

  bool hasThread(String parentEventId) {
    final separator = parentEventId.lastIndexOf('-');
    if (separator == -1) return false;
    final index = int.tryParse(parentEventId.substring(separator + 1));
    return index != null && index > 0 && index % 17 == 13;
  }

  Signal<List<ThreadReply>> repliesFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    final key = _key(roomId, parent.id);
    return _threads.putIfAbsent(key, () {
      if (!hasThread(parent.id)) return signal(const <ThreadReply>[]);
      return signal(
        List<ThreadReply>.unmodifiable(<ThreadReply>[
          ThreadReply(
            id: '${parent.id}-thread-0',
            sender: parent.mine ? 'Alice' : parent.sender,
            body:
                'I pulled the details into this thread so the room stays tidy.',
            mine: false,
            timeLabel: '10:18',
          ),
          ThreadReply(
            id: '${parent.id}-thread-1',
            sender: 'You',
            body: 'Perfect. I’ll keep the follow-up here.',
            mine: true,
            timeLabel: '10:21',
          ),
          ThreadReply(
            id: '${parent.id}-thread-2',
            sender: parent.mine ? 'Alice' : parent.sender,
            body: 'Done — the latest update is ready to review.',
            mine: false,
            timeLabel: '10:24',
          ),
        ]),
      );
    });
  }

  ThreadReply sendReply({
    required String roomId,
    required TimelineMessage parent,
    required String rawBody,
  }) {
    final body = rawBody.trim();
    if (body.isEmpty) {
      throw ArgumentError.value(rawBody, 'rawBody', 'Reply cannot be empty');
    }
    final transactionId = 'kite-thread-${_transactionCounter++}';
    final reply = ThreadReply(
      id: transactionId,
      sender: 'You',
      body: body,
      mine: true,
      timeLabel: 'now',
      sendState: TimelineSendState.sending,
    );
    final replies = repliesFor(roomId: roomId, parent: parent);
    replies.value = List<ThreadReply>.unmodifiable(<ThreadReply>[
      ...replies.value,
      reply,
    ]);
    unawaited(_settle(roomId: roomId, parent: parent, reply: reply));
    return reply;
  }

  void reset({ThreadSendPort? sendPort}) {
    if (sendPort != null) _sendPort = sendPort;
    _transactionCounter = 0;
    _threads.clear();
  }

  Future<void> _settle({
    required String roomId,
    required TimelineMessage parent,
    required ThreadReply reply,
  }) async {
    final outcome = await _sendPort.sendReply(
      roomId: roomId,
      parentEventId: parent.id,
      transactionId: reply.id,
      body: reply.body,
    );
    reply.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
  }

  String _key(String roomId, String parentEventId) => '$roomId::$parentEventId';
}

final threadController = ThreadController();
