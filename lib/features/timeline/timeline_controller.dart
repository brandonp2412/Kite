import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:signals/signals.dart';

enum TimelineSendState { sending, sent, failed }

enum TimelineSendOutcome { sent, failed }

enum TimelineAttachmentKind { image, video, file }

enum TimelineLocationKind { staticLocation, liveLocation }

enum TimelineLocationPermission { granted, denied, permanentlyDenied }

@immutable
final class TimelinePollOption {
  const TimelinePollOption({required this.id, required this.label});

  final String id;
  final String label;
}

@immutable
final class TimelinePoll {
  TimelinePoll({
    required this.question,
    required List<TimelinePollOption> options,
    Map<String, int> voteCounts = const <String, int>{},
    this.selectedOptionId,
    this.isEnded = false,
    this.isEnding = false,
  }) : options = List<TimelinePollOption>.unmodifiable(options),
       voteCounts = Map<String, int>.unmodifiable(voteCounts);

  final String question;
  final List<TimelinePollOption> options;
  final Map<String, int> voteCounts;
  final String? selectedOptionId;
  final bool isEnded;
  final bool isEnding;

  int get totalVotes => voteCounts.values.fold(0, (sum, count) => sum + count);

  int votesFor(String optionId) => voteCounts[optionId] ?? 0;

  TimelinePoll select(String optionId) {
    if (isEnded || !options.any((option) => option.id == optionId)) return this;
    if (selectedOptionId == optionId) return this;
    final next = Map<String, int>.of(voteCounts);
    final previous = selectedOptionId;
    if (previous != null) {
      final previousCount = next[previous] ?? 0;
      if (previousCount <= 1) {
        next.remove(previous);
      } else {
        next[previous] = previousCount - 1;
      }
    }
    next[optionId] = (next[optionId] ?? 0) + 1;
    return TimelinePoll(
      question: question,
      options: options,
      voteCounts: next,
      selectedOptionId: optionId,
      isEnded: isEnded,
      isEnding: isEnding,
    );
  }

  TimelinePoll withEnding(bool value) => TimelinePoll(
    question: question,
    options: options,
    voteCounts: voteCounts,
    selectedOptionId: selectedOptionId,
    isEnded: isEnded,
    isEnding: value,
  );

  TimelinePoll ended() => TimelinePoll(
    question: question,
    options: options,
    voteCounts: voteCounts,
    selectedOptionId: selectedOptionId,
    isEnded: true,
    isEnding: false,
  );
}

abstract interface class TimelinePollPort {
  Future<TimelineSendOutcome> createPoll({
    required String roomId,
    required String transactionId,
    required TimelinePoll poll,
  });

  Future<TimelineSendOutcome> votePoll({
    required String roomId,
    required String eventId,
    required String optionId,
  });

  Future<TimelineSendOutcome> endPoll({
    required String roomId,
    required String eventId,
  });
}

final class DeterministicTimelinePollPort implements TimelinePollPort {
  DeterministicTimelinePollPort({
    this.latency = const Duration(milliseconds: 120),
  });

  final Duration latency;
  final List<String> createdEventIds = <String>[];
  final List<({String eventId, String optionId})> votes =
      <({String eventId, String optionId})>[];
  final List<String> endedEventIds = <String>[];

  @override
  Future<TimelineSendOutcome> createPoll({
    required String roomId,
    required String transactionId,
    required TimelinePoll poll,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    createdEventIds.add(transactionId);
    return TimelineSendOutcome.sent;
  }

  @override
  Future<TimelineSendOutcome> votePoll({
    required String roomId,
    required String eventId,
    required String optionId,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    votes.add((eventId: eventId, optionId: optionId));
    return TimelineSendOutcome.sent;
  }

  @override
  Future<TimelineSendOutcome> endPoll({
    required String roomId,
    required String eventId,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    endedEventIds.add(eventId);
    return TimelineSendOutcome.sent;
  }
}

@immutable
final class TimelineLocationPreparation {
  const TimelineLocationPreparation({required this.permission, this.location});

  final TimelineLocationPermission permission;
  final TimelineLocation? location;

  bool get isReady =>
      permission == TimelineLocationPermission.granted && location != null;
}

abstract interface class TimelineLocationPort {
  Future<TimelineLocationPreparation> prepare(TimelineLocationKind kind);
  Future<TimelineSendOutcome> sendLocation({
    required String roomId,
    required String transactionId,
    required TimelineLocation location,
  });
  Future<TimelineSendOutcome> stopLiveLocation({
    required String roomId,
    required String eventId,
  });
  Future<void> openAppSettings();
}

final class DeterministicTimelineLocationPort implements TimelineLocationPort {
  DeterministicTimelineLocationPort({
    this.permission = TimelineLocationPermission.granted,
    this.latency = const Duration(milliseconds: 120),
    this.label = 'Britomart',
    this.latitude = -36.8468,
    this.longitude = 174.7682,
  });

  TimelineLocationPermission permission;
  final Duration latency;
  final String label;
  final double latitude;
  final double longitude;
  int prepareRequests = 0;
  int settingsRequests = 0;
  final List<TimelineLocation> sentLocations = <TimelineLocation>[];
  final List<String> stoppedEventIds = <String>[];

  @override
  Future<TimelineLocationPreparation> prepare(TimelineLocationKind kind) async {
    prepareRequests++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (permission != TimelineLocationPermission.granted) {
      return TimelineLocationPreparation(permission: permission);
    }
    return TimelineLocationPreparation(
      permission: permission,
      location: TimelineLocation(
        kind: kind,
        latitude: latitude,
        longitude: longitude,
        label: label,
        isLiveActive: kind == TimelineLocationKind.liveLocation,
      ),
    );
  }

  @override
  Future<TimelineSendOutcome> sendLocation({
    required String roomId,
    required String transactionId,
    required TimelineLocation location,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    sentLocations.add(location);
    return TimelineSendOutcome.sent;
  }

  @override
  Future<TimelineSendOutcome> stopLiveLocation({
    required String roomId,
    required String eventId,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    stoppedEventIds.add(eventId);
    return TimelineSendOutcome.sent;
  }

  @override
  Future<void> openAppSettings() async {
    settingsRequests++;
  }
}

@immutable
final class TimelineLocation {
  const TimelineLocation({
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.label,
    this.isLiveActive = false,
    this.isLiveStopping = false,
  });

  final TimelineLocationKind kind;
  final double latitude;
  final double longitude;
  final String label;
  final bool isLiveActive;
  final bool isLiveStopping;

  TimelineLocation copyWith({
    double? latitude,
    double? longitude,
    String? label,
    bool? isLiveActive,
    bool? isLiveStopping,
  }) {
    return TimelineLocation(
      kind: kind,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      label: label ?? this.label,
      isLiveActive: isLiveActive ?? this.isLiveActive,
      isLiveStopping: isLiveStopping ?? this.isLiveStopping,
    );
  }
}

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

@immutable
final class TimelineShareRequest {
  const TimelineShareRequest({
    required this.roomId,
    required this.eventId,
    required this.body,
    this.attachment,
  });

  final String roomId;
  final String eventId;
  final String body;
  final TimelineAttachment? attachment;
}

abstract interface class TimelineSharePort {
  Future<void> shareMessage(TimelineShareRequest request);
}

final class DeterministicTimelineSharePort implements TimelineSharePort {
  DeterministicTimelineSharePort({
    this.latency = const Duration(milliseconds: 80),
  });

  final Duration latency;
  final List<TimelineShareRequest> shares = <TimelineShareRequest>[];

  @override
  Future<void> shareMessage(TimelineShareRequest request) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    shares.add(request);
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
    TimelineLocation? location,
    TimelinePoll? poll,
    TimelineSendState sendState = TimelineSendState.sent,
    bool edited = false,
    bool redacted = false,
    List<String> editHistory = const <String>[],
    Map<String, TimelineReactionSummary> reactions = const {},
    List<String> readBy = const <String>[],
  }) : bodyText = signal(body),
       editedState = signal(edited),
       redactedState = signal(redacted),
       editHistoryState = signal<List<String>>(
         List<String>.unmodifiable(editHistory),
       ),
       reactionState = signal<Map<String, TimelineReactionSummary>>(
         Map<String, TimelineReactionSummary>.unmodifiable(reactions),
       ),
       readByState = signal<List<String>>(List<String>.unmodifiable(readBy)),
       locationState = signal<TimelineLocation?>(location),
       pollState = signal<TimelinePoll?>(poll),
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
  final Signal<TimelineLocation?> locationState;
  final Signal<TimelinePoll?> pollState;
  final Signal<bool> editedState;
  final Signal<bool> redactedState;
  final Signal<List<String>> editHistoryState;
  final Signal<Map<String, TimelineReactionSummary>> reactionState;
  final Signal<List<String>> readByState;
  final Signal<TimelineSendState> sendState;

  String get body => bodyText.value;
  bool get edited => editedState.value;
  bool get redacted => redactedState.value;
  List<String> get editHistory => editHistoryState.value;
  bool get isReply => replyToMessageId != null;
  Map<String, TimelineReactionSummary> get reactions => reactionState.value;
  List<String> get readBy => readByState.value;
  TimelineLocation? get location => locationState.value;
  TimelinePoll? get poll => pollState.value;
}

abstract interface class TimelineLocationShareDelegate {
  Future<TimelineLocationPreparation> prepareLocation(
    TimelineLocationKind kind,
  );
  Future<void> openLocationSettings();
  void sendLocation(String roomId, TimelineLocation location);
}

class TimelineController implements TimelineLocationShareDelegate {
  TimelineController({
    TimelineSendPort? sendPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
    TimelineSharePort? sharePort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineLocationPort? locationPort,
    TimelinePollPort? pollPort,
  }) : _sendPort = sendPort ?? DeterministicTimelineSendPort(),
       _attachmentSendPort =
           attachmentSendPort ??
           const DeterministicTimelineAttachmentSendPort(),
       _moderationPort =
           moderationPort ?? DeterministicTimelineModerationPort(),
       _sharePort = sharePort ?? DeterministicTimelineSharePort(),
       _linkOpenPort = linkOpenPort ?? DeterministicTimelineLinkOpenPort(),
       _locationPort = locationPort ?? DeterministicTimelineLocationPort(),
       _pollPort = pollPort ?? DeterministicTimelinePollPort() {
    reset();
  }

  TimelineSendPort _sendPort;
  TimelineAttachmentSendPort _attachmentSendPort;
  TimelineModerationPort _moderationPort;
  TimelineSharePort _sharePort;
  TimelineLinkOpenPort _linkOpenPort;
  TimelineLocationPort _locationPort;
  TimelinePollPort _pollPort;
  final Map<String, Signal<List<TimelineMessage>>> _messages =
      <String, Signal<List<TimelineMessage>>>{};
  final Map<String, Signal<List<String>>> _typingUsers =
      <String, Signal<List<String>>>{};
  final Map<String, Signal<String?>> _unreadMarkerEventIds =
      <String, Signal<String?>>{};
  int _transactionCounter = 0;

  Signal<String?> unreadMarkerFor(String roomId) {
    return _unreadMarkerEventIds.putIfAbsent(
      roomId,
      () => signal<String?>(null),
    );
  }

  void setUnreadMarker(String roomId, String? eventId) {
    if (eventId != null &&
        !messagesFor(roomId).peek().any((message) => message.id == eventId)) {
      throw ArgumentError.value(eventId, 'eventId', 'Unknown timeline event.');
    }
    final marker = unreadMarkerFor(roomId);
    if (marker.peek() == eventId) return;
    marker.value = eventId;
  }

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

  void updateLocation(
    String roomId,
    String eventId,
    TimelineLocation location,
  ) {
    final matches = messagesFor(roomId)
        .peek()
        .where((candidate) => candidate.id == eventId);
    if (matches.isEmpty) return;
    final target = matches.single;
    final current = target.locationState.peek();
    if (current == null || current.kind != location.kind) return;
    target.locationState.value = location;
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

  @override
  Future<TimelineLocationPreparation> prepareLocation(
    TimelineLocationKind kind,
  ) => _locationPort.prepare(kind);

  @override
  Future<void> openLocationSettings() => _locationPort.openAppSettings();

  @override
  TimelineMessage sendLocation(String roomId, TimelineLocation location) {
    final transactionId = 'kite-local-${_transactionCounter++}';
    final message = TimelineMessage(
      id: transactionId,
      sender: 'You',
      body: '',
      mine: true,
      timeLabel: 'now',
      location: location,
      sendState: TimelineSendState.sending,
    );
    final roomMessages = messagesFor(roomId);
    roomMessages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...roomMessages.value,
      message,
    ]);
    unawaited(_settleLocation(roomId, message));
    return message;
  }

  TimelineMessage sendPoll(
    String roomId, {
    required String question,
    required List<String> options,
  }) {
    final normalizedQuestion = question.trim();
    final normalizedOptions = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    if (normalizedQuestion.isEmpty) {
      throw ArgumentError.value(
        question,
        'question',
        'Poll question is required',
      );
    }
    if (normalizedOptions.length < 2 || normalizedOptions.length > 6) {
      throw ArgumentError.value(
        options,
        'options',
        'Polls require between 2 and 6 choices',
      );
    }
    if (normalizedOptions.toSet().length != normalizedOptions.length) {
      throw ArgumentError.value(
        options,
        'options',
        'Poll choices must be unique',
      );
    }

    final transactionId = 'kite-local-${_transactionCounter++}';
    final poll = TimelinePoll(
      question: normalizedQuestion,
      options: <TimelinePollOption>[
        for (var index = 0; index < normalizedOptions.length; index++)
          TimelinePollOption(
            id: 'option-$index',
            label: normalizedOptions[index],
          ),
      ],
    );
    final message = TimelineMessage(
      id: transactionId,
      sender: 'You',
      body: '',
      mine: true,
      timeLabel: 'now',
      poll: poll,
      sendState: TimelineSendState.sending,
    );
    final roomMessages = messagesFor(roomId);
    roomMessages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...roomMessages.value,
      message,
    ]);
    unawaited(_settlePoll(roomId, message));
    return message;
  }

  void updatePoll(String roomId, String eventId, TimelinePoll poll) {
    final matches = messagesFor(roomId)
        .peek()
        .where((candidate) => candidate.id == eventId);
    if (matches.isEmpty) return;
    final message = matches.single;
    if (message.pollState.peek() == null) return;
    message.pollState.value = poll;
  }

  Future<bool> votePoll(
    String roomId,
    TimelineMessage message,
    String optionId,
  ) async {
    final current = message.pollState.peek();
    if (current == null || current.isEnded || current.isEnding) return false;
    final next = current.select(optionId);
    if (identical(next, current)) return false;
    message.pollState.value = next;
    final outcome = await _pollPort.votePoll(
      roomId: roomId,
      eventId: message.id,
      optionId: optionId,
    );
    if (outcome == TimelineSendOutcome.sent) return true;
    if (identical(message.pollState.peek(), next)) {
      message.pollState.value = current;
    }
    return false;
  }

  Future<bool> endPoll(String roomId, TimelineMessage message) async {
    final current = message.pollState.peek();
    if (!message.mine ||
        current == null ||
        current.isEnded ||
        current.isEnding) {
      return false;
    }
    final ending = current.withEnding(true);
    message.pollState.value = ending;
    final outcome = await _pollPort.endPoll(
      roomId: roomId,
      eventId: message.id,
    );
    if (outcome == TimelineSendOutcome.sent) {
      message.pollState.value = ending.ended();
      return true;
    }
    if (identical(message.pollState.peek(), ending)) {
      message.pollState.value = current;
    }
    return false;
  }

  Future<bool> stopLiveLocation(String roomId, TimelineMessage message) async {
    final current = message.locationState.peek();
    if (!message.mine ||
        current == null ||
        current.kind != TimelineLocationKind.liveLocation ||
        !current.isLiveActive ||
        current.isLiveStopping) {
      return false;
    }
    message.locationState.value = current.copyWith(isLiveStopping: true);
    final outcome = await _locationPort.stopLiveLocation(
      roomId: roomId,
      eventId: message.id,
    );
    final latest = message.locationState.peek();
    if (latest == null || latest.kind != TimelineLocationKind.liveLocation) {
      return false;
    }
    if (outcome == TimelineSendOutcome.sent) {
      message.locationState.value = latest.copyWith(
        isLiveActive: false,
        isLiveStopping: false,
      );
      return true;
    }
    message.locationState.value = latest.copyWith(isLiveStopping: false);
    return false;
  }

  void editText(TimelineMessage message, String rawBody) {
    if (!message.mine || message.redacted) return;
    final body = rawBody.trim();
    if (body.isEmpty || body == message.body) return;
    batch(() {
      message.editHistoryState.value = List<String>.unmodifiable(<String>[
        ...message.editHistoryState.peek(),
        message.body,
      ]);
      message.bodyText.value = body;
      message.editedState.value = true;
    });
  }

  void redactText(TimelineMessage message) {
    if (!message.mine || message.redacted) return;
    batch(() {
      message.bodyText.value = '';
      message.editedState.value = false;
      message.editHistoryState.value = const <String>[];
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

  Future<void> shareMessage(String roomId, TimelineMessage message) {
    if (message.redacted) return Future<void>.value();
    return _sharePort.shareMessage(
      TimelineShareRequest(
        roomId: roomId,
        eventId: message.id,
        body: message.body,
        attachment: message.attachment,
      ),
    );
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

  Future<void> openLink(Uri uri) => _linkOpenPort.open(uri);

  void retry(String roomId, TimelineMessage message) {
    if (message.sendState.value != TimelineSendState.failed) return;
    message.sendState.value = TimelineSendState.sending;
    if (message.poll != null) {
      unawaited(_settlePoll(roomId, message));
    } else if (message.location != null) {
      unawaited(_settleLocation(roomId, message));
    } else if (message.attachment != null) {
      unawaited(_settleAttachment(roomId, message));
    } else {
      unawaited(_settle(roomId, message));
    }
  }

  void reset({
    TimelineSendPort? sendPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
    TimelineSharePort? sharePort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineLocationPort? locationPort,
    TimelinePollPort? pollPort,
  }) {
    if (sendPort != null) _sendPort = sendPort;
    if (attachmentSendPort != null) _attachmentSendPort = attachmentSendPort;
    if (moderationPort != null) _moderationPort = moderationPort;
    if (sharePort != null) _sharePort = sharePort;
    if (linkOpenPort != null) _linkOpenPort = linkOpenPort;
    if (locationPort != null) _locationPort = locationPort;
    if (pollPort != null) _pollPort = pollPort;
    _transactionCounter = 0;
    _messages.clear();
    _typingUsers.clear();
    _unreadMarkerEventIds.clear();
  }

  Future<void> _settlePoll(String roomId, TimelineMessage message) async {
    final poll = message.pollState.peek();
    if (poll == null) return;
    final outcome = await _pollPort.createPoll(
      roomId: roomId,
      transactionId: message.id,
      poll: poll,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
  }

  Future<void> _settleLocation(String roomId, TimelineMessage message) async {
    final location = message.locationState.peek();
    if (location == null) return;
    final outcome = await _locationPort.sendLocation(
      roomId: roomId,
      transactionId: message.id,
      location: location,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
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
