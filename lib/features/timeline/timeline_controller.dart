import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:signals/signals.dart';

enum TimelineSendState { sending, sent, failed }

enum TimelineSendOutcome { sent, failed }

enum TimelineAttachmentKind { image, video, file }

@immutable
final class TimelineAttachment {
  const TimelineAttachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.sizeLabel,
  });

  final String id;
  final TimelineAttachmentKind kind;
  final String name;
  final String sizeLabel;
}

abstract interface class TimelineAttachmentSendPort {
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  });
}

final class DeterministicTimelineAttachmentSendPort
    implements TimelineAttachmentSendPort {
  const DeterministicTimelineAttachmentSendPort({
    this.latency = const Duration(milliseconds: 220),
  });

  final Duration latency;

  @override
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  }) async {
    await Future<void>.delayed(latency);
    return TimelineSendOutcome.sent;
  }
}

@immutable
final class TimelineReportRequest {
  const TimelineReportRequest({
    required this.roomId,
    required this.eventId,
    required this.reason,
  });

  final String roomId;
  final String eventId;
  final String reason;
}

abstract interface class TimelineModerationPort {
  Future<void> reportMessage(TimelineReportRequest request);
}

final class DeterministicTimelineModerationPort
    implements TimelineModerationPort {
  DeterministicTimelineModerationPort({
    this.latency = const Duration(milliseconds: 120),
  });

  final Duration latency;
  final List<TimelineReportRequest> reports = <TimelineReportRequest>[];

  @override
  Future<void> reportMessage(TimelineReportRequest request) async {
    await Future<void>.delayed(latency);
    reports.add(request);
  }
}

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
final class TimelineReactionSummary {
  const TimelineReactionSummary({
    required this.emoji,
    required this.reactors,
    required this.reactedByMe,
  });

  final String emoji;
  final List<String> reactors;
  final bool reactedByMe;

  int get count => reactors.length;

  TimelineReactionSummary copyWith({
    List<String>? reactors,
    bool? reactedByMe,
  }) {
    return TimelineReactionSummary(
      emoji: emoji,
      reactors: List<String>.unmodifiable(reactors ?? this.reactors),
      reactedByMe: reactedByMe ?? this.reactedByMe,
    );
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
    this.attachment,
    TimelineSendState sendState = TimelineSendState.sent,
    bool edited = false,
    bool redacted = false,
    Map<String, TimelineReactionSummary> reactions = const {},
    List<String> readBy = const <String>[],
  }) : bodyText = signal(body),
       editedState = signal(edited),
       redactedState = signal(redacted),
       reactionState = signal<Map<String, TimelineReactionSummary>>(
         Map<String, TimelineReactionSummary>.unmodifiable(reactions),
       ),
       readByState = signal<List<String>>(List<String>.unmodifiable(readBy)),
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
  final TimelineAttachment? attachment;
  final Signal<bool> editedState;
  final Signal<bool> redactedState;
  final Signal<Map<String, TimelineReactionSummary>> reactionState;
  final Signal<List<String>> readByState;
  final Signal<TimelineSendState> sendState;

  String get body => bodyText.value;
  bool get edited => editedState.value;
  bool get redacted => redactedState.value;
  bool get isReply => replyToMessageId != null;
  Map<String, TimelineReactionSummary> get reactions => reactionState.value;
  List<String> get readBy => readByState.value;
}

class TimelineController {
  TimelineController({
    TimelineSendPort? sendPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
  }) : _sendPort = sendPort ?? DeterministicTimelineSendPort(),
       _attachmentSendPort =
           attachmentSendPort ??
           const DeterministicTimelineAttachmentSendPort(),
       _moderationPort =
           moderationPort ?? DeterministicTimelineModerationPort() {
    reset();
  }

  TimelineSendPort _sendPort;
  TimelineAttachmentSendPort _attachmentSendPort;
  TimelineModerationPort _moderationPort;
  final Map<String, Signal<List<TimelineMessage>>> _messages =
      <String, Signal<List<TimelineMessage>>>{};
  final Map<String, Signal<List<String>>> _typingUsers =
      <String, Signal<List<String>>>{};
  int _transactionCounter = 0;

  Signal<List<String>> typingUsersFor(String roomId) {
    return _typingUsers.putIfAbsent(
      roomId,
      () => signal<List<String>>(const <String>[]),
    );
  }

  void updateTypingUsers(String roomId, Iterable<String> users) {
    final next =
        users
            .map((user) => user.trim())
            .where((user) => user.isNotEmpty && user != 'You')
            .toSet()
            .toList(growable: false)
          ..sort();
    final signal = typingUsersFor(roomId);
    if (listEquals(signal.peek(), next)) return;
    signal.value = List<String>.unmodifiable(next);
  }

  void updateReadReceipts(
    String roomId,
    String eventId,
    Iterable<String> readers,
  ) {
    final message = messagesFor(roomId)
        .peek()
        .where((candidate) => candidate.id == eventId);
    if (message.isEmpty) return;
    final target = message.single;
    if (!target.mine || target.redacted) return;
    final next =
        readers
            .map((reader) => reader.trim())
            .where((reader) => reader.isNotEmpty && reader != 'You')
            .toSet()
            .toList(growable: false)
          ..sort();
    if (listEquals(target.readByState.peek(), next)) return;
    target.readByState.value = List<String>.unmodifiable(next);
  }

  Signal<List<TimelineMessage>> messagesFor(String roomId) {
    return _messages.putIfAbsent(roomId, () {
      final fixture = BenchmarkFixture.messagesFor(roomId);
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

  TimelineMessage sendAttachment(
    String roomId,
    TimelineAttachment attachment, {
    String caption = '',
    TimelineMessage? replyTo,
  }) {
    final body = caption.trim();
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
      attachment: attachment,
      sendState: TimelineSendState.sending,
    );
    final roomMessages = messagesFor(roomId);
    roomMessages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...roomMessages.value,
      message,
    ]);
    unawaited(_settleAttachment(roomId, message));
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
      message.reactionState.value = const <String, TimelineReactionSummary>{};
      message.readByState.value = const <String>[];
      message.redactedState.value = true;
    });
  }

  void toggleReaction(TimelineMessage message, String emoji) {
    if (message.redacted || emoji.isEmpty) return;
    final current = message.reactions;
    final existing = current[emoji];
    final next = Map<String, TimelineReactionSummary>.of(current);
    if (existing?.reactedByMe ?? false) {
      final reactors = existing!.reactors
          .where((reactor) => reactor != 'You')
          .toList(growable: false);
      if (reactors.isEmpty) {
        next.remove(emoji);
      } else {
        next[emoji] = existing.copyWith(reactors: reactors, reactedByMe: false);
      }
    } else if (existing == null) {
      next[emoji] = TimelineReactionSummary(
        emoji: emoji,
        reactors: const <String>['You'],
        reactedByMe: true,
      );
    } else {
      next[emoji] = existing.copyWith(
        reactors: <String>[...existing.reactors, 'You'],
        reactedByMe: true,
      );
    }
    message.reactionState.value =
        Map<String, TimelineReactionSummary>.unmodifiable(next);
  }

  List<TimelineMessage> forwardText(
    TimelineMessage source,
    Iterable<String> roomIds,
  ) {
    if (source.redacted) return const <TimelineMessage>[];
    final destinations = roomIds.toSet().toList(growable: false);
    return List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      for (final roomId in destinations) sendText(roomId, source.body),
    ]);
  }

  Future<void> reportMessage(
    String roomId,
    TimelineMessage message,
    String reason,
  ) {
    if (message.redacted || reason.trim().isEmpty) {
      return Future<void>.value();
    }
    return _moderationPort.reportMessage(
      TimelineReportRequest(
        roomId: roomId,
        eventId: message.id,
        reason: reason.trim(),
      ),
    );
  }

  void retry(String roomId, TimelineMessage message) {
    if (message.sendState.value != TimelineSendState.failed) return;
    message.sendState.value = TimelineSendState.sending;
    if (message.attachment != null) {
      unawaited(_settleAttachment(roomId, message));
    } else {
      unawaited(_settle(roomId, message));
    }
  }

  void reset({
    TimelineSendPort? sendPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
  }) {
    if (sendPort != null) _sendPort = sendPort;
    if (attachmentSendPort != null) _attachmentSendPort = attachmentSendPort;
    if (moderationPort != null) _moderationPort = moderationPort;
    _transactionCounter = 0;
    _messages.clear();
    _typingUsers.clear();
  }

  Future<void> _settleAttachment(String roomId, TimelineMessage message) async {
    final attachment = message.attachment;
    if (attachment == null) return;
    final outcome = await _attachmentSendPort.sendAttachment(
      roomId: roomId,
      transactionId: message.id,
      attachment: attachment,
      caption: message.body,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
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
