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
    required String body,
    required this.mine,
    required this.timeLabel,
    this.replyToMessageId,
    this.replyToSender,
    this.replyToBody,
    TimelineSendState sendState = TimelineSendState.sent,
    bool edited = false,
    bool redacted = false,
    Map<String, List<String>> reactions = const <String, List<String>>{},
  }) : bodyText = signal(body),
       editedState = signal(edited),
       redactedState = signal(redacted),
       reactionsState = signal(_freezeReactions(reactions)),
       sendState = signal(sendState);

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
  final Signal<String> bodyText;
  final bool mine;
  final String timeLabel;
  final String? replyToMessageId;
  final String? replyToSender;
  final String? replyToBody;
  final Signal<bool> editedState;
  final Signal<bool> redactedState;
  final Signal<Map<String, List<String>>> reactionsState;
  final Signal<TimelineSendState> sendState;

  String get body => bodyText.value;
  bool get edited => editedState.value;
  bool get redacted => redactedState.value;
  Map<String, List<String>> get reactions => reactionsState.value;
  bool get isReply => replyToMessageId != null;

  static Map<String, List<String>> _freezeReactions(
    Map<String, List<String>> source,
  ) {
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final entry in source.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }
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

  TimelineMessage sendText(
    String roomId,
    String rawBody, {
    TimelineMessage? replyTo,
  }) {
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
      replyToMessageId: replyTo?.id,
      replyToSender: replyTo?.sender,
      replyToBody: replyTo?.body,
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

  void editText(TimelineMessage message, String rawBody) {
    if (!message.mine || message.redacted) return;
    final body = rawBody.trim();
    if (body.isEmpty || body == message.body) return;
    message.bodyText.value = body;
    message.editedState.value = true;
  }

  void redactText(TimelineMessage message) {
    if (!message.mine || message.redacted) return;
    batch(() {
      message.bodyText.value = '';
      message.editedState.value = false;
      message.redactedState.value = true;
      message.reactionsState.value = const <String, List<String>>{};
    });
  }

  void toggleReaction(
    TimelineMessage message,
    String emoji, {
    String reactor = 'You',
  }) {
    if (message.redacted || emoji.trim().isEmpty) return;
    final next = <String, List<String>>{
      for (final entry in message.reactions.entries)
        entry.key: List<String>.of(entry.value),
    };
    final reactors = next.putIfAbsent(emoji, () => <String>[]);
    if (reactors.contains(reactor)) {
      reactors.remove(reactor);
      if (reactors.isEmpty) next.remove(emoji);
    } else {
      reactors.add(reactor);
    }
    message.reactionsState.value = TimelineMessage._freezeReactions(next);
  }

  List<String> reactorsFor(TimelineMessage message, String emoji) {
    return message.reactions[emoji] ?? const <String>[];
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
