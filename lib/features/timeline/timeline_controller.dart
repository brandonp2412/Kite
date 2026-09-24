import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:signals/signals.dart';

enum TimelineSendState { sending, sent, failed }

enum TimelineSendOutcome { sent, failed }

enum TimelineAttachmentKind { image, video, file, audio, voice }

extension TimelineAttachmentKindProperties on TimelineAttachmentKind {
  bool get isVisualMedia =>
      this == TimelineAttachmentKind.image ||
      this == TimelineAttachmentKind.video;

  bool get isAudio =>
      this == TimelineAttachmentKind.audio ||
      this == TimelineAttachmentKind.voice;
}

enum TimelineAudioPlaybackState { paused, playing }

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
    this.durationLabel,
    this.contentUri,
    this.encryptedFile,
    this.thumbnailContentUri,
    this.encryptedThumbnailFile,
  });

  final String id;
  final TimelineAttachmentKind kind;
  final String name;
  final String sizeLabel;
  final String? durationLabel;
  final String? contentUri;
  final Map<String, Object?>? encryptedFile;
  final String? thumbnailContentUri;
  final Map<String, Object?>? encryptedThumbnailFile;
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

typedef TimelineFixtureProvider = List<BenchmarkMessage> Function(
  String roomId,
);

abstract interface class TimelineSendPort {
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
  });
}

abstract interface class TimelineEditPort {
  Future<TimelineSendOutcome> editText({
    required String roomId,
    required String transactionId,
    required String eventId,
    required String body,
  });
}

abstract interface class TimelineRedactionPort {
  Future<TimelineSendOutcome> redactEvent({
    required String roomId,
    required String transactionId,
    required String eventId,
  });
}

final class DeterministicTimelineRedactionPort
    implements TimelineRedactionPort {
  const DeterministicTimelineRedactionPort({
    this.latency = Duration.zero,
    this.outcome = TimelineSendOutcome.sent,
  });

  final Duration latency;
  final TimelineSendOutcome outcome;

  @override
  Future<TimelineSendOutcome> redactEvent({
    required String roomId,
    required String transactionId,
    required String eventId,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return outcome;
  }
}

final class DeterministicTimelineEditPort implements TimelineEditPort {
  const DeterministicTimelineEditPort({
    this.latency = const Duration(milliseconds: 120),
  });

  final Duration latency;

  @override
  Future<TimelineSendOutcome> editText({
    required String roomId,
    required String transactionId,
    required String eventId,
    required String body,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return TimelineSendOutcome.sent;
  }
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
    String? replyToEventId,
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
    String? formattedBody,
    this.senderId,
    this.senderAvatarUrl,
    required this.timeLabel,
    this.sentAt,
    this.replyToMessageId,
    this.replyToSender,
    this.replyToBody,
    this.transactionId,
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
       formattedBodyText = signal(formattedBody),
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
       audioPlaybackState = signal(TimelineAudioPlaybackState.paused),
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

  static TimelineMessage? fromMatrixEvent(
    MatrixTimelineEvent event, {
    required String currentUserId,
    TimelineMessage? replyTarget,
  }) {
    if (event.type != 'm.room.message') return null;
    final localTime = event.originServerTimestamp.toLocal();
    if (event.redacted) {
      return TimelineMessage(
        id: event.eventId,
        sender: event.senderDisplayName ?? event.senderId,
        body: '',
        mine: event.senderId == currentUserId,
        senderId: event.senderId,
        senderAvatarUrl: event.senderAvatarUrl,
        sentAt: localTime,
        timeLabel:
            '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}',
        redacted: true,
      );
    }
    final content = event.content;
    final msgtype = content['msgtype'];
    if (msgtype is! String) return null;
    final rawBody = content['body'];
    final body = rawBody is String ? rawBody.trim() : '';
    final attachment = _matrixAttachment(event, msgtype, body);
    final supportedText =
        msgtype == 'm.text' || msgtype == 'm.notice' || msgtype == 'm.emote';
    if (!supportedText && attachment == null) return null;

    final mediaBody = attachment == null ? body : _matrixMediaCaption(content);
    final replyToMessageId = _matrixReplyToEventId(content);
    final formattedBody = _matrixFormattedBody(content);
    return TimelineMessage(
      id: event.eventId,
      sender: event.senderDisplayName ?? event.senderId,
      body: mediaBody,
      formattedBody: attachment == null ? formattedBody : null,
      mine: event.senderId == currentUserId,
      senderId: event.senderId,
      senderAvatarUrl: event.senderAvatarUrl,
      sentAt: localTime,
      timeLabel:
          '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}',
      replyToMessageId: replyToMessageId,
      replyToSender: replyToMessageId == null ? null : replyTarget?.sender,
      replyToBody: replyToMessageId == null ? null : replyTarget?.body,
      attachment: attachment,
    );
  }

  final String id;
  final String sender;
  final Signal<String> bodyText;
  final Signal<String?> formattedBodyText;
  final bool mine;
  final String? senderId;
  final String? senderAvatarUrl;
  final String timeLabel;
  final DateTime? sentAt;
  final String? replyToMessageId;
  final String? replyToSender;
  final String? replyToBody;
  final String? transactionId;
  final TimelineAttachment? attachment;
  final Signal<TimelineLocation?> locationState;
  final Signal<TimelinePoll?> pollState;
  final Signal<TimelineAudioPlaybackState> audioPlaybackState;
  final Signal<bool> editedState;
  final Signal<bool> redactedState;
  final Signal<List<String>> editHistoryState;
  final Signal<Map<String, TimelineReactionSummary>> reactionState;
  final Signal<List<String>> readByState;
  final Signal<TimelineSendState> sendState;

  String get body => bodyText.value;
  String? get formattedBody => formattedBodyText.value;
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
    TimelineEditPort? editPort,
    TimelineRedactionPort? redactionPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
    TimelineSharePort? sharePort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineLocationPort? locationPort,
    TimelinePollPort? pollPort,
    TimelineFixtureProvider? fixtureProvider,
  }) : _sendPort = sendPort ?? DeterministicTimelineSendPort(),
       _editPort = editPort ?? const DeterministicTimelineEditPort(),
       _redactionPort =
           redactionPort ?? const DeterministicTimelineRedactionPort(),
       _fixtureProvider = fixtureProvider ?? BenchmarkFixture.messagesFor,
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
  TimelineEditPort _editPort;
  TimelineRedactionPort _redactionPort;
  TimelineFixtureProvider _fixtureProvider;
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
  int _matrixTransactionCounter = 0;
  final String _matrixTransactionNamespace = _secureTransactionNamespace();

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

  void applyFullyReadMarker(
    String roomId,
    String? fullyReadEventId, {
    required int unreadMessageCount,
    Iterable<MatrixTimelineEvent>? timelineEvents,
  }) {
    if (unreadMessageCount < 0) {
      throw ArgumentError.value(
        unreadMessageCount,
        'unreadMessageCount',
        'Unread message count cannot be negative.',
      );
    }

    final messages = messagesFor(roomId).peek();
    if (messages.isEmpty || unreadMessageCount == 0) {
      setUnreadMarker(roomId, null);
      return;
    }

    if (fullyReadEventId != null && timelineEvents != null) {
      final events = timelineEvents.toList(growable: false);
      final fullyReadIndex = events.indexWhere(
        (event) => event.eventId == fullyReadEventId,
      );
      if (fullyReadIndex >= 0) {
        final renderedIds = <String>{
          for (final message in messages) message.id,
        };
        for (
          var index = fullyReadIndex + 1;
          index < events.length;
          index += 1
        ) {
          if (renderedIds.contains(events[index].eventId)) {
            setUnreadMarker(roomId, events[index].eventId);
            return;
          }
        }
        setUnreadMarker(roomId, null);
        return;
      }

      setUnreadMarker(roomId, messages.first.id);
      return;
    }

    var markerIndex = -1;
    if (fullyReadEventId != null) {
      final fullyReadIndex = messages.indexWhere(
        (message) => message.id == fullyReadEventId,
      );
      if (fullyReadIndex >= 0 && fullyReadIndex + 1 < messages.length) {
        markerIndex = fullyReadIndex + 1;
      } else if (fullyReadIndex == messages.length - 1) {
        setUnreadMarker(roomId, null);
        return;
      }
    }

    if (markerIndex < 0) {
      markerIndex = unreadMessageCount >= messages.length
          ? 0
          : messages.length - unreadMessageCount;
    }
    setUnreadMarker(roomId, messages[markerIndex].id);
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

  void applyReadReceipts(String roomId, Iterable<MatrixReadReceipt> receipts) {
    final messages = messagesFor(roomId).peek();
    final eventIndexes = <String, int>{
      for (var index = 0; index < messages.length; index += 1)
        messages[index].id: index,
    };
    final readersByEvent = <String, List<String>>{};
    final resolvedReaders = <String>{};

    for (final receipt in receipts) {
      final receiptIndex = eventIndexes[receipt.eventId];
      if (receiptIndex == null) continue;
      for (var index = receiptIndex; index >= 0; index -= 1) {
        final candidate = messages[index];
        if (!candidate.mine || candidate.redacted) continue;
        readersByEvent
            .putIfAbsent(candidate.id, () => <String>[])
            .add(receipt.displayName);
        resolvedReaders.add(receipt.displayName);
        break;
      }
    }

    for (final message in messages) {
      if (!message.mine || message.redacted) continue;
      final next = <String>[
        for (final reader in message.readByState.peek())
          if (!resolvedReaders.contains(reader)) reader,
        ...?readersByEvent[message.id],
      ];
      updateReadReceipts(roomId, message.id, next);
    }
  }

  Signal<List<TimelineMessage>> messagesFor(String roomId) {
    return _messages.putIfAbsent(roomId, () {
      final fixture = _fixtureProvider(roomId);
      return signal(
        List<TimelineMessage>.unmodifiable(<TimelineMessage>[
          for (var index = 0; index < fixture.length; index++)
            TimelineMessage.fromFixture(fixture[index], index),
        ]),
      );
    });
  }

  void applyMatrixEvents(
    String roomId,
    Iterable<MatrixTimelineEvent> events, {
    required String currentUserId,
  }) {
    final target = _messages.putIfAbsent(
      roomId,
      () => signal<List<TimelineMessage>>(const <TimelineMessage>[]),
    );
    final current = target.peek();
    final existingById = <String, TimelineMessage>{
      for (final message in current) message.id: message,
    };
    final projected = <TimelineMessage>[];
    final projectedById = <String, TimelineMessage>{};
    final pendingReplacements = <String, List<MatrixTimelineEvent>>{};
    final pendingRedactions = <String>{};
    final echoedTransactionIds = <String>{};
    for (final event in events) {
      if (event.roomId != roomId) continue;
      final transactionId = event.transactionId;
      if (transactionId != null) echoedTransactionIds.add(transactionId);
      if (event.type == 'm.room.redaction') {
        final redactsEventId = event.redactsEventId;
        if (redactsEventId == null) continue;
        final redactionTarget = projectedById[redactsEventId];
        if (redactionTarget == null) {
          pendingRedactions.add(redactsEventId);
        } else {
          _applyMatrixRedaction(redactionTarget);
        }
        continue;
      }
      final replacement = _matrixReplacement(event.content);
      if (replacement != null) {
        final replacementTarget = projectedById[replacement.eventId];
        if (replacementTarget == null) {
          pendingReplacements
              .putIfAbsent(replacement.eventId, () => <MatrixTimelineEvent>[])
              .add(event);
        } else {
          _applyMatrixReplacement(
            replacementTarget,
            event,
            replacement.body,
            replacement.formattedBody,
          );
        }
        continue;
      }
      final replyToEventId = _matrixReplyToEventId(event.content);
      final mapped = TimelineMessage.fromMatrixEvent(
        event,
        currentUserId: currentUserId,
        replyTarget: replyToEventId == null
            ? null
            : projectedById[replyToEventId] ?? existingById[replyToEventId],
      );
      if (mapped == null) continue;
      projected.add(mapped);
      projectedById[mapped.id] = mapped;
      if (pendingRedactions.remove(mapped.id)) {
        _applyMatrixRedaction(mapped);
      }
      final deferredReplacements = pendingReplacements.remove(mapped.id);
      if (deferredReplacements != null) {
        for (final replacementEvent in deferredReplacements) {
          final deferred = _matrixReplacement(replacementEvent.content);
          if (deferred != null) {
            _applyMatrixReplacement(
              mapped,
              replacementEvent,
              deferred.body,
              deferred.formattedBody,
            );
          }
        }
      }
    }
    for (var index = 0; index < projected.length; index++) {
      final mapped = projected[index];
      final existing = existingById[mapped.id];
      if (existing == null ||
          !_sameMatrixProjectionStructure(existing, mapped)) {
        continue;
      }
      _applyMatrixProjectionLeaves(existing, mapped);
      projected[index] = existing;
      projectedById[mapped.id] = existing;
    }
    projected.addAll(
      current.where(
        (message) =>
            message.id.startsWith('kite-local-') &&
            !echoedTransactionIds.contains(message.id) &&
            (message.transactionId == null ||
                !echoedTransactionIds.contains(message.transactionId)) &&
            !projected.any((candidate) => candidate.id == message.id),
      ),
    );
    final next = List<TimelineMessage>.unmodifiable(projected);
    if (_sameMessageIdentityList(current, next)) return;
    target.value = next;
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

    final localId = 'kite-local-${_transactionCounter++}';
    final message = TimelineMessage(
      id: localId,
      transactionId: _nextMatrixTransactionId(),
      sender: 'You',
      body: body,
      mine: true,
      timeLabel: 'now',
      sentAt: DateTime.now(),
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
    final localId = 'kite-local-${_transactionCounter++}';
    final message = TimelineMessage(
      id: localId,
      transactionId: _nextMatrixTransactionId(),
      sender: 'You',
      body: body,
      mine: true,
      timeLabel: 'now',
      sentAt: DateTime.now(),
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
    final localId = 'kite-local-${_transactionCounter++}';
    final message = TimelineMessage(
      id: localId,
      transactionId: _nextMatrixTransactionId(),
      sender: 'You',
      body: '',
      mine: true,
      timeLabel: 'now',
      sentAt: DateTime.now(),
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

    final localId = 'kite-local-${_transactionCounter++}';
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
      id: localId,
      transactionId: _nextMatrixTransactionId(),
      sender: 'You',
      body: '',
      mine: true,
      timeLabel: 'now',
      sentAt: DateTime.now(),
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

  void editText(String roomId, TimelineMessage message, String rawBody) {
    if (!message.mine || message.redacted) return;
    final body = rawBody.trim();
    if (body.isEmpty || body == message.body) return;
    final previousBody = message.body;
    final previousEdited = message.edited;
    final previousHistory = message.editHistory;
    final nextHistory = List<String>.unmodifiable(<String>[
      ...previousHistory,
      previousBody,
    ]);
    batch(() {
      message.editHistoryState.value = nextHistory;
      message.bodyText.value = body;
      message.editedState.value = true;
    });
    unawaited(
      _settleEdit(
        roomId,
        message,
        body,
        previousBody: previousBody,
        previousEdited: previousEdited,
        previousHistory: previousHistory,
      ),
    );
  }

  Future<bool> redactText(String roomId, TimelineMessage message) async {
    if (!message.mine || message.redacted) return false;
    final previousBody = message.body;
    final previousFormattedBody = message.formattedBodyText.peek();
    final previousEdited = message.edited;
    final previousHistory = message.editHistoryState.peek();
    final previousReactions = message.reactionState.peek();
    final previousReadBy = message.readByState.peek();
    batch(() {
      message.bodyText.value = '';
      message.formattedBodyText.value = null;
      message.editedState.value = false;
      message.editHistoryState.value = const <String>[];
      message.reactionState.value = const <String, TimelineReactionSummary>{};
      message.readByState.value = const <String>[];
      message.redactedState.value = true;
    });
    final outcome = await _redactionPort.redactEvent(
      roomId: roomId,
      transactionId: _nextMatrixTransactionId(),
      eventId: message.id,
    );
    if (outcome == TimelineSendOutcome.sent) return true;
    if (message.redacted) {
      batch(() {
        message.bodyText.value = previousBody;
        message.formattedBodyText.value = previousFormattedBody;
        message.editedState.value = previousEdited;
        message.editHistoryState.value = previousHistory;
        message.reactionState.value = previousReactions;
        message.readByState.value = previousReadBy;
        message.redactedState.value = false;
      });
    }
    return false;
  }

  void toggleAudioPlayback(TimelineMessage message) {
    final kind = message.attachment?.kind;
    if (message.redacted || kind == null || !kind.isAudio) return;
    message.audioPlaybackState.value =
        message.audioPlaybackState.peek() == TimelineAudioPlaybackState.playing
        ? TimelineAudioPlaybackState.paused
        : TimelineAudioPlaybackState.playing;
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

  void updateTransport({
    required TimelineSendPort sendPort,
    TimelineEditPort? editPort,
    TimelineRedactionPort? redactionPort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineSharePort? sharePort,
    TimelineModerationPort? moderationPort,
  }) {
    _sendPort = sendPort;
    _editPort = editPort ?? const DeterministicTimelineEditPort();
    _redactionPort =
        redactionPort ?? const DeterministicTimelineRedactionPort();
    _linkOpenPort = linkOpenPort ?? DeterministicTimelineLinkOpenPort();
    _sharePort = sharePort ?? DeterministicTimelineSharePort();
    _moderationPort = moderationPort ?? DeterministicTimelineModerationPort();
  }

  void reset({
    TimelineSendPort? sendPort,
    TimelineEditPort? editPort,
    TimelineRedactionPort? redactionPort,
    TimelineAttachmentSendPort? attachmentSendPort,
    TimelineModerationPort? moderationPort,
    TimelineSharePort? sharePort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineLocationPort? locationPort,
    TimelinePollPort? pollPort,
    TimelineFixtureProvider? fixtureProvider,
  }) {
    if (sendPort != null) _sendPort = sendPort;
    if (editPort != null) _editPort = editPort;
    if (redactionPort != null) _redactionPort = redactionPort;
    if (fixtureProvider != null) _fixtureProvider = fixtureProvider;
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
      transactionId: message.transactionId ?? message.id,
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
      transactionId: message.transactionId ?? message.id,
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
      transactionId: message.transactionId ?? message.id,
      attachment: attachment,
      caption: message.body,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
  }

  Future<void> _settleEdit(
    String roomId,
    TimelineMessage message,
    String body, {
    required String previousBody,
    required bool previousEdited,
    required List<String> previousHistory,
  }) async {
    final outcome = await _editPort.editText(
      roomId: roomId,
      transactionId: _nextMatrixTransactionId(),
      eventId: message.id,
      body: body,
    );
    if (outcome == TimelineSendOutcome.sent || message.body != body) return;
    batch(() {
      message.bodyText.value = previousBody;
      message.editedState.value = previousEdited;
      message.editHistoryState.value = List<String>.unmodifiable(
        previousHistory,
      );
    });
  }

  Future<void> _settle(String roomId, TimelineMessage message) async {
    final outcome = await _sendPort.sendText(
      roomId: roomId,
      transactionId: message.transactionId ?? message.id,
      body: message.body,
      replyToEventId: message.replyToMessageId,
    );
    message.sendState.value = switch (outcome) {
      TimelineSendOutcome.sent => TimelineSendState.sent,
      TimelineSendOutcome.failed => TimelineSendState.failed,
    };
  }

  String _nextMatrixTransactionId() =>
      'kite-txn-$_matrixTransactionNamespace-${_matrixTransactionCounter++}';
}

String _secureTransactionNamespace() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

({String eventId, String body, String? formattedBody})? _matrixReplacement(
  Map<String, Object?> content,
) {
  final relatesTo = content['m.relates_to'];
  if (relatesTo is! Map || relatesTo['rel_type'] != 'm.replace') return null;
  final eventId = relatesTo['event_id'];
  final newContent = content['m.new_content'];
  if (eventId is! String || newContent is! Map) return null;
  final body = newContent['body'];
  final msgtype = newContent['msgtype'];
  final normalizedEventId = eventId.trim();
  final normalizedBody = body is String ? body.trim() : '';
  if (normalizedEventId.isEmpty ||
      normalizedBody.isEmpty ||
      (msgtype != 'm.text' && msgtype != 'm.notice' && msgtype != 'm.emote')) {
    return null;
  }
  return (
    eventId: normalizedEventId,
    body: normalizedBody,
    formattedBody: _matrixFormattedBody(Map<String, Object?>.from(newContent)),
  );
}

String? _matrixFormattedBody(Map<String, Object?> content) {
  if (content['format'] != 'org.matrix.custom.html') return null;
  final formattedBody = content['formatted_body'];
  if (formattedBody is! String) return null;
  final normalized = formattedBody.trim();
  return normalized.isEmpty ? null : normalized;
}

void _applyMatrixRedaction(TimelineMessage target) {
  if (target.redacted) return;
  batch(() {
    target.bodyText.value = '';
    target.formattedBodyText.value = null;
    target.editedState.value = false;
    target.redactedState.value = true;
    target.editHistoryState.value = const <String>[];
    target.reactionState.value = const <String, TimelineReactionSummary>{};
    target.readByState.value = const <String>[];
  });
}

void _applyMatrixReplacement(
  TimelineMessage target,
  MatrixTimelineEvent replacementEvent,
  String body,
  String? formattedBody,
) {
  if (target.redacted ||
      target.attachment != null ||
      target.senderId == null ||
      target.senderId != replacementEvent.senderId ||
      (target.body == body &&
          target.formattedBodyText.peek() == formattedBody)) {
    return;
  }
  batch(() {
    target.editHistoryState.value = List<String>.unmodifiable(<String>[
      ...target.editHistoryState.peek(),
      target.body,
    ]);
    target.bodyText.value = body;
    target.formattedBodyText.value = formattedBody;
    target.editedState.value = true;
  });
}

String? _matrixReplyToEventId(Map<String, Object?> content) {
  final relatesTo = content['m.relates_to'];
  if (relatesTo is! Map) return null;
  final inReplyTo = relatesTo['m.in_reply_to'];
  if (inReplyTo is! Map) return null;
  final eventId = inReplyTo['event_id'];
  if (eventId is! String) return null;
  final normalized = eventId.trim();
  return normalized.isEmpty ? null : normalized;
}

TimelineAttachment? _matrixAttachment(
  MatrixTimelineEvent event,
  String msgtype,
  String body,
) {
  final info = event.content['info'];
  final infoMap = info is Map ? info : const <Object?, Object?>{};
  final mimetype = infoMap['mimetype'];
  final mime = mimetype is String ? mimetype.toLowerCase() : '';
  final kind = switch (msgtype) {
    'm.image' => TimelineAttachmentKind.image,
    'm.video' => TimelineAttachmentKind.video,
    'm.audio' =>
      _isMatrixVoiceMessage(event.content)
          ? TimelineAttachmentKind.voice
          : TimelineAttachmentKind.audio,
    'm.file' when mime.startsWith('audio/') => TimelineAttachmentKind.audio,
    'm.file' => TimelineAttachmentKind.file,
    _ => null,
  };
  if (kind == null) return null;

  final filename = event.content['filename'];
  final name = filename is String && filename.trim().isNotEmpty
      ? filename.trim()
      : body.isNotEmpty
      ? body
      : _defaultAttachmentName(kind);
  final size = infoMap['size'];
  final sizeLabel = size is int && size >= 0
      ? '${_formatBytes(size)} · ${_attachmentKindLabel(kind)}'
      : _attachmentKindLabel(kind);
  final duration = infoMap['duration'];
  final durationLabel = duration is int && duration >= 0
      ? _formatDuration(Duration(milliseconds: duration))
      : null;
  final url = event.content['url'];
  final file = event.content['file'];
  final encryptedFile = file is Map
      ? Map<String, Object?>.unmodifiable(<String, Object?>{
          for (final entry in file.entries)
            if (entry.key is String) entry.key as String: entry.value,
        })
      : null;
  final encryptedUrl = encryptedFile?['url'];
  final contentUri = switch ((url, encryptedUrl)) {
    (final String value, _) when value.startsWith('mxc://') => value,
    (_, final String value) when value.startsWith('mxc://') => value,
    _ => null,
  };
  final thumbnailUrl = infoMap['thumbnail_url'];
  final thumbnailFile = infoMap['thumbnail_file'];
  final encryptedThumbnailFile = thumbnailFile is Map
      ? Map<String, Object?>.unmodifiable(<String, Object?>{
          for (final entry in thumbnailFile.entries)
            if (entry.key is String) entry.key as String: entry.value,
        })
      : null;
  final encryptedThumbnailUrl = encryptedThumbnailFile?['url'];
  final thumbnailContentUri = switch ((thumbnailUrl, encryptedThumbnailUrl)) {
    (final String value, _) when value.startsWith('mxc://') => value,
    (_, final String value) when value.startsWith('mxc://') => value,
    _ => null,
  };
  return TimelineAttachment(
    id: contentUri ?? event.eventId,
    kind: kind,
    name: name,
    sizeLabel: sizeLabel,
    durationLabel: durationLabel,
    contentUri: contentUri,
    encryptedFile: encryptedFile,
    thumbnailContentUri: thumbnailContentUri,
    encryptedThumbnailFile: encryptedThumbnailFile,
  );
}

bool _isMatrixVoiceMessage(Map<String, Object?> content) {
  return content.containsKey('org.matrix.msc3245.voice') ||
      content.containsKey('m.voice');
}

String _matrixMediaCaption(Map<String, Object?> content) {
  final caption = content['org.matrix.msc1767.caption'];
  return caption is String ? caption.trim() : '';
}

String _defaultAttachmentName(TimelineAttachmentKind kind) => switch (kind) {
  TimelineAttachmentKind.image => 'Image',
  TimelineAttachmentKind.video => 'Video',
  TimelineAttachmentKind.file => 'File',
  TimelineAttachmentKind.audio => 'Audio',
  TimelineAttachmentKind.voice => 'Voice message',
};

String _attachmentKindLabel(TimelineAttachmentKind kind) => switch (kind) {
  TimelineAttachmentKind.image => 'Image',
  TimelineAttachmentKind.video => 'Video',
  TimelineAttachmentKind.file => 'File',
  TimelineAttachmentKind.audio => 'Audio',
  TimelineAttachmentKind.voice => 'Voice',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

bool _sameMatrixProjectionStructure(
  TimelineMessage left,
  TimelineMessage right,
) {
  final leftAttachment = left.attachment;
  final rightAttachment = right.attachment;
  return left.id == right.id &&
      left.sender == right.sender &&
      left.senderId == right.senderId &&
      left.mine == right.mine &&
      left.timeLabel == right.timeLabel &&
      left.replyToMessageId == right.replyToMessageId &&
      left.replyToSender == right.replyToSender &&
      left.replyToBody == right.replyToBody &&
      leftAttachment?.id == rightAttachment?.id &&
      leftAttachment?.kind == rightAttachment?.kind &&
      leftAttachment?.name == rightAttachment?.name &&
      leftAttachment?.sizeLabel == rightAttachment?.sizeLabel &&
      leftAttachment?.durationLabel == rightAttachment?.durationLabel;
}

void _applyMatrixProjectionLeaves(
  TimelineMessage target,
  TimelineMessage projection,
) {
  if (projection.redacted) {
    _applyMatrixRedaction(target);
    return;
  }
  if (target.edited &&
      target.editHistoryState.peek().length >
          projection.editHistoryState.peek().length) {
    return;
  }
  batch(() {
    if (target.bodyText.peek() != projection.bodyText.peek()) {
      target.bodyText.value = projection.bodyText.peek();
    }
    if (target.formattedBodyText.peek() !=
        projection.formattedBodyText.peek()) {
      target.formattedBodyText.value = projection.formattedBodyText.peek();
    }
    if (target.editedState.peek() != projection.editedState.peek()) {
      target.editedState.value = projection.editedState.peek();
    }
    if (!listEquals(
      target.editHistoryState.peek(),
      projection.editHistoryState.peek(),
    )) {
      target.editHistoryState.value = List<String>.unmodifiable(
        projection.editHistoryState.peek(),
      );
    }
  });
}

bool _sameMessageIdentityList(
  List<TimelineMessage> left,
  List<TimelineMessage> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}

final timelineController = TimelineController();
