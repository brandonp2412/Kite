import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:signals/signals.dart';

enum TimelineSendState { sending, sent, failed }

enum TimelineSendOutcome { sent, failed }

abstract interface class TimelineSendPort {
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  });
}

class DeterministicTimelineSendPort implements TimelineSendPort {
  DeterministicTimelineSendPort({
    this.latency = const Duration(milliseconds: 180),
  });

  final Duration latency;
  final Set<String> _failedOnce = <String>{};

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  }) async {
    await Future<void>.delayed(latency);
    if (body == '[deterministic-fail-once]' && _failedOnce.add(transactionId)) {
      return TimelineSendOutcome.failed;
    }
    return TimelineSendOutcome.sent;
  }
}

@immutable
class TimelineMessage {
  TimelineMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.mine,
    required this.timeLabel,
    TimelineSendState sendState = TimelineSendState.sent,
  }) : sendState = signal(sendState);

  factory TimelineMessage.fromFixture(BenchmarkMessage message, int index) {
    final minute = (index * 7) % 60;
    final hour = 9 + ((index ~/ 9) % 4);
    return TimelineMessage(
      id: message.id,
      sender: message.sender,
      body: message.body,
      mine: message.mine,
      timeLabel:
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    );
  }

  final String id;
  final String sender;
  final String body;
  final bool mine;
  final String timeLabel;
  final Signal<TimelineSendState> sendState;
}

class TimelineController {
  TimelineController({TimelineSendPort? sendPort})
    : _sendPort = sendPort ?? DeterministicTimelineSendPort() {
    reset();
  }

  TimelineSendPort _sendPort;
  final Map<String, Signal<List<TimelineMessage>>> _messages =
      <String, Signal<List<TimelineMessage>>>{};
  int _transactionCounter = 0;

  Signal<List<TimelineMessage>> messagesFor(String roomId) {
    return _messages.putIfAbsent(roomId, () {
      final fixture = BenchmarkFixture.messages[roomId];
      if (fixture == null) return signal(const <TimelineMessage>[]);
      return signal(
        List<TimelineMessage>.unmodifiable(<TimelineMessage>[
          for (var index = 0; index < fixture.length; index++)
            TimelineMessage.fromFixture(fixture[index], index),
        ]),
      );
    });
  }

  TimelineMessage sendText(String roomId, String rawBody) {
    final body = rawBody.trim();
    if (body.isEmpty) {
      throw ArgumentError.value(rawBody, 'rawBody', 'Message cannot be empty');
    }

    final transactionId = 'kite-local-${_transactionCounter++}';
    final message = TimelineMessage(
      id: transactionId,
      sender: 'You',
      body: body,
      mine: true,
      timeLabel: 'now',
      sendState: TimelineSendState.sending,
    );
    final roomMessages = messagesFor(roomId);
    roomMessages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...roomMessages.value,
      message,
    ]);
    unawaited(_settle(roomId, message));
    return message;
  }

  void retry(String roomId, TimelineMessage message) {
    if (message.sendState.value != TimelineSendState.failed) return;
    message.sendState.value = TimelineSendState.sending;
    unawaited(_settle(roomId, message));
  }

  void reset({TimelineSendPort? sendPort}) {
    if (sendPort != null) _sendPort = sendPort;
    _transactionCounter = 0;
    _messages.clear();
  }

  Future<void> _settle(String roomId, TimelineMessage message) async {
    final outcome = await _sendPort.sendText(
      roomId: roomId,
      transactionId: message.id,
      body: message.body,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
  }
}

final timelineController = TimelineController();
