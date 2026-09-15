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

abstract interface class ThreadAttachmentSendPort {
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  });
}

abstract interface class ThreadLocationPort {
  Future<TimelineLocationPreparation> prepare(TimelineLocationKind kind);
  Future<TimelineSendOutcome> sendLocation({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineLocation location,
  });
  Future<void> openAppSettings();
}

enum ThreadSubscriptionOutcome { applied, failed }

abstract interface class ThreadSubscriptionPort {
  Future<ThreadSubscriptionOutcome> setFollowing({
    required String roomId,
    required String parentEventId,
    required bool following,
  });
}

enum ThreadComposerAction { text, staticLocation, liveLocation }

@immutable
class ThreadPage {
  const ThreadPage({required this.replies, required this.hasMore});

  final List<ThreadReply> replies;
  final bool hasMore;
}

abstract interface class ThreadPaginationPort {
  Future<ThreadPage> loadOlder({
    required String roomId,
    required String parentEventId,
    required String? beforeReplyId,
  });
}

class DeterministicThreadPaginationPort implements ThreadPaginationPort {
  const DeterministicThreadPaginationPort({
    this.latency = const Duration(milliseconds: 90),
    this.pageSize = 2,
  }) : assert(pageSize > 0);

  final Duration latency;
  final int pageSize;

  @override
  Future<ThreadPage> loadOlder({
    required String roomId,
    required String parentEventId,
    required String? beforeReplyId,
  }) async {
    await Future<void>.delayed(latency);
    if (beforeReplyId?.contains('-thread-older-') ?? false) {
      return const ThreadPage(replies: <ThreadReply>[], hasMore: false);
    }
    return ThreadPage(
      replies: List<ThreadReply>.generate(pageSize, (index) {
        return ThreadReply(
          id: '$parentEventId-thread-older-$index',
          sender: index.isEven ? 'Mina' : 'You',
          body: switch (index) {
            0 => 'I added the earlier context here.',
            1 => 'Thanks — that fills in the missing part.',
            _ => 'Earlier thread context ${index + 1}',
          },
          mine: index.isOdd,
          timeLabel: '09:${(30 + index).toString().padLeft(2, '0')}',
        );
      }, growable: false),
      hasMore: false,
    );
  }
}

class DeterministicThreadSubscriptionPort implements ThreadSubscriptionPort {
  const DeterministicThreadSubscriptionPort({
    this.latency = const Duration(milliseconds: 90),
  });

  final Duration latency;

  @override
  Future<ThreadSubscriptionOutcome> setFollowing({
    required String roomId,
    required String parentEventId,
    required bool following,
  }) async {
    await Future<void>.delayed(latency);
    return ThreadSubscriptionOutcome.applied;
  }
}

class DeterministicThreadLocationPort implements ThreadLocationPort {
  DeterministicThreadLocationPort({
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
  final List<({String parentEventId, TimelineLocation location})>
  sentLocations = <({String parentEventId, TimelineLocation location})>[];

  @override
  Future<TimelineLocationPreparation> prepare(TimelineLocationKind kind) async {
    prepareRequests += 1;
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
        isLiveActive: false,
      ),
    );
  }

  @override
  Future<TimelineSendOutcome> sendLocation({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineLocation location,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    sentLocations.add((parentEventId: parentEventId, location: location));
    return TimelineSendOutcome.sent;
  }

  @override
  Future<void> openAppSettings() async {
    settingsRequests += 1;
  }
}

class DeterministicThreadAttachmentSendPort
    implements ThreadAttachmentSendPort {
  const DeterministicThreadAttachmentSendPort({
    this.latency = const Duration(milliseconds: 140),
  });

  final Duration latency;

  @override
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  }) async {
    await Future<void>.delayed(latency);
    return TimelineSendOutcome.sent;
  }
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
    this.attachment,
    this.location,
    TimelineSendState sendState = TimelineSendState.sent,
    Iterable<String> readBy = const <String>[],
  }) : sendState = signal(sendState),
       readByState = signal(List<String>.unmodifiable(readBy)),
       audioPlaybackState = signal(TimelineAudioPlaybackState.paused);

  final String id;
  final String sender;
  final String body;
  final bool mine;
  final String timeLabel;
  final TimelineAttachment? attachment;
  final TimelineLocation? location;
  final Signal<TimelineSendState> sendState;
  final Signal<List<String>> readByState;
  final Signal<TimelineAudioPlaybackState> audioPlaybackState;

  List<String> get readBy => readByState.value;
}

class ThreadController {
  ThreadController({
    ThreadSendPort? sendPort,
    ThreadAttachmentSendPort? attachmentSendPort,
    ThreadLocationPort? locationPort,
    ThreadPaginationPort? paginationPort,
    ThreadSubscriptionPort? subscriptionPort,
  }) : _sendPort = sendPort ?? const DeterministicThreadSendPort(),
       _attachmentSendPort =
           attachmentSendPort ?? const DeterministicThreadAttachmentSendPort(),
       _locationPort = locationPort ?? DeterministicThreadLocationPort(),
       _paginationPort =
           paginationPort ?? const DeterministicThreadPaginationPort(),
       _subscriptionPort =
           subscriptionPort ?? const DeterministicThreadSubscriptionPort();

  ThreadSendPort _sendPort;
  ThreadAttachmentSendPort _attachmentSendPort;
  ThreadLocationPort _locationPort;
  ThreadPaginationPort _paginationPort;
  ThreadSubscriptionPort _subscriptionPort;
  final Map<String, Signal<List<ThreadReply>>> _threads =
      <String, Signal<List<ThreadReply>>>{};
  final Map<String, Signal<bool>> _hasMore = <String, Signal<bool>>{};
  final Map<String, Signal<bool>> _isLoadingOlder = <String, Signal<bool>>{};
  final Map<String, Signal<bool>> _paginationFailed = <String, Signal<bool>>{};
  final Map<String, Signal<int>> _unreadCount = <String, Signal<int>>{};
  final Map<String, Signal<int>> _roomUnreadThreadCount =
      <String, Signal<int>>{};
  final Map<String, Signal<String?>> _latestReadReplyId =
      <String, Signal<String?>>{};
  final Map<String, Signal<String?>> _focusedReplyId =
      <String, Signal<String?>>{};
  final Map<String, Signal<bool>> _isFollowing = <String, Signal<bool>>{};
  final Map<String, Signal<bool>> _isUpdatingSubscription =
      <String, Signal<bool>>{};
  final Map<String, Signal<bool>> _subscriptionFailed =
      <String, Signal<bool>>{};
  final Set<String> _runtimeThreadParentIds = <String>{};
  int _transactionCounter = 0;

  bool hasThread(String parentEventId) {
    if (_runtimeThreadParentIds.contains(parentEventId)) return true;

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
      final replies = List<ThreadReply>.unmodifiable(<ThreadReply>[
        ThreadReply(
          id: '${parent.id}-thread-0',
          sender: parent.mine ? 'Alice' : parent.sender,
          body: 'I pulled the details into this thread so the room stays tidy.',
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
      ]);
      _hasMore.putIfAbsent(key, () => signal(true));
      _isLoadingOlder.putIfAbsent(key, () => signal(false));
      _paginationFailed.putIfAbsent(key, () => signal(false));
      _unreadCount.putIfAbsent(key, () => signal(2));
      _latestReadReplyId.putIfAbsent(key, () => signal(replies.first.id));
      return signal(replies);
    });
  }

  void applyThreadSnapshot({
    required String roomId,
    required TimelineMessage parent,
    required List<ThreadReply> replies,
    required bool hasMore,
    required int unreadCount,
    String? latestReadReplyId,
  }) {
    if (unreadCount < 0 || unreadCount > replies.length) {
      throw ArgumentError.value(
        unreadCount,
        'unreadCount',
        'Unread reply count must be between zero and the reply count',
      );
    }
    final key = _key(roomId, parent.id);
    final snapshot = List<ThreadReply>.unmodifiable(replies);
    _threads.putIfAbsent(key, () => signal(snapshot)).value = snapshot;
    _hasMore.putIfAbsent(key, () => signal(hasMore)).value = hasMore;
    _isLoadingOlder.putIfAbsent(key, () => signal(false)).value = false;
    _paginationFailed.putIfAbsent(key, () => signal(false)).value = false;
    _unreadCount.putIfAbsent(key, () => signal(unreadCount)).value =
        unreadCount;
    _latestReadReplyId.putIfAbsent(key, () => signal(latestReadReplyId)).value =
        latestReadReplyId;
    if (snapshot.isEmpty) {
      _runtimeThreadParentIds.remove(parent.id);
    } else {
      _runtimeThreadParentIds.add(parent.id);
    }
  }

  Signal<bool> hasMoreFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _hasMore[_key(roomId, parent.id)] ?? signal(false);
  }

  Signal<bool> isLoadingOlderFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _isLoadingOlder[_key(roomId, parent.id)] ?? signal(false);
  }

  Signal<bool> paginationFailedFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _paginationFailed[_key(roomId, parent.id)] ?? signal(false);
  }

  Signal<int> unreadCountFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _unreadCount[_key(roomId, parent.id)] ?? signal(0);
  }

  Signal<int> unreadThreadCountForRoom(String roomId) {
    return _roomUnreadThreadCount.putIfAbsent(roomId, () => signal(0));
  }

  void updateRoomUnreadThreadCount({
    required String roomId,
    required int unreadThreadCount,
  }) {
    if (unreadThreadCount < 0) {
      throw ArgumentError.value(
        unreadThreadCount,
        'unreadThreadCount',
        'Unread thread count cannot be negative',
      );
    }
    unreadThreadCountForRoom(roomId).value = unreadThreadCount;
  }

  void markRoomThreadsRead(String roomId) {
    final prefix = '$roomId::';
    for (final entry in _unreadCount.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      entry.value.value = 0;
      final replies = _threads[entry.key]?.peek() ?? const <ThreadReply>[];
      _latestReadReplyId[entry.key]?.value = replies.isEmpty
          ? null
          : replies.last.id;
    }
    _roomUnreadThreadCount[roomId]?.value = 0;
  }

  bool supportsComposerAction(ThreadComposerAction action) {
    return action != ThreadComposerAction.liveLocation;
  }

  Future<TimelineLocationPreparation> prepareLocation(
    TimelineLocationKind kind,
  ) {
    requireSupportedComposerAction(
      kind == TimelineLocationKind.liveLocation
          ? ThreadComposerAction.liveLocation
          : ThreadComposerAction.staticLocation,
    );
    return _locationPort.prepare(kind);
  }

  Future<void> openLocationSettings() => _locationPort.openAppSettings();

  void requireSupportedComposerAction(ThreadComposerAction action) {
    if (!supportsComposerAction(action)) {
      throw UnsupportedError(
        'Live location sharing is not supported in threads',
      );
    }
  }

  Signal<bool> isFollowingFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _isFollowing.putIfAbsent(
      _key(roomId, parent.id),
      () => signal(false),
    );
  }

  Signal<bool> isUpdatingSubscriptionFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _isUpdatingSubscription.putIfAbsent(
      _key(roomId, parent.id),
      () => signal(false),
    );
  }

  Signal<bool> subscriptionFailedFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _subscriptionFailed.putIfAbsent(
      _key(roomId, parent.id),
      () => signal(false),
    );
  }

  Future<void> toggleFollowing({
    required String roomId,
    required TimelineMessage parent,
  }) async {
    final following = isFollowingFor(roomId: roomId, parent: parent);
    final updating = isUpdatingSubscriptionFor(roomId: roomId, parent: parent);
    final failed = subscriptionFailedFor(roomId: roomId, parent: parent);
    if (updating.value) return;

    final target = !following.value;
    updating.value = true;
    failed.value = false;
    try {
      final outcome = await _subscriptionPort.setFollowing(
        roomId: roomId,
        parentEventId: parent.id,
        following: target,
      );
      if (outcome == ThreadSubscriptionOutcome.applied) {
        following.value = target;
      } else {
        failed.value = true;
      }
    } catch (_) {
      failed.value = true;
    } finally {
      updating.value = false;
    }
  }

  Signal<String?> latestReadReplyIdFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _latestReadReplyId[_key(roomId, parent.id)] ?? signal(null);
  }

  Signal<String?> focusedReplyIdFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _focusedReplyId.putIfAbsent(
      _key(roomId, parent.id),
      () => signal(null),
    );
  }

  void focusReply({
    required String roomId,
    required TimelineMessage parent,
    required String replyId,
  }) {
    focusedReplyIdFor(roomId: roomId, parent: parent).value = replyId;
  }

  void clearFocus({
    required String roomId,
    required TimelineMessage parent,
    String? onlyIfReplyId,
  }) {
    final focus = focusedReplyIdFor(roomId: roomId, parent: parent);
    if (onlyIfReplyId != null && focus.value != onlyIfReplyId) return;
    focus.value = null;
  }

  void updateReadReceipts({
    required String roomId,
    required TimelineMessage parent,
    required String replyId,
    required Iterable<String> readers,
  }) {
    final replies = repliesFor(roomId: roomId, parent: parent).peek();
    final matches = replies.where((reply) => reply.id == replyId);
    if (matches.isEmpty) return;
    final reply = matches.single;
    if (!reply.mine || reply.sendState.peek() != TimelineSendState.sent) return;

    final next =
        readers
            .map((reader) => reader.trim())
            .where((reader) => reader.isNotEmpty && reader != 'You')
            .toSet()
            .toList(growable: false)
          ..sort();
    if (listEquals(reply.readByState.peek(), next)) return;
    reply.readByState.value = List<String>.unmodifiable(next);
  }

  void markRead({required String roomId, required TimelineMessage parent}) {
    final replies = repliesFor(roomId: roomId, parent: parent).value;
    final key = _key(roomId, parent.id);
    final previouslyUnread = _unreadCount[key]?.value ?? 0;
    _unreadCount[key]?.value = 0;
    if (previouslyUnread > 0) {
      final roomUnread = unreadThreadCountForRoom(roomId);
      final nextUnread = roomUnread.value - previouslyUnread;
      roomUnread.value = nextUnread < 0 ? 0 : nextUnread;
    }
    _latestReadReplyId[key]?.value = replies.isEmpty ? null : replies.last.id;
  }

  Future<bool> ensureReplyAvailable({
    required String roomId,
    required TimelineMessage parent,
    required String replyId,
    int maxPages = 20,
  }) async {
    if (maxPages < 0) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must not be negative');
    }
    final replies = repliesFor(roomId: roomId, parent: parent);
    if (replies.value.any((reply) => reply.id == replyId)) return true;

    var remainingPages = maxPages;
    while (remainingPages > 0 &&
        hasMoreFor(roomId: roomId, parent: parent).value) {
      final previousLength = replies.value.length;
      await loadOlder(roomId: roomId, parent: parent);
      if (replies.value.any((reply) => reply.id == replyId)) return true;
      if (replies.value.length == previousLength) break;
      remainingPages -= 1;
    }
    return false;
  }

  Future<void> loadOlder({
    required String roomId,
    required TimelineMessage parent,
  }) async {
    final replies = repliesFor(roomId: roomId, parent: parent);
    final key = _key(roomId, parent.id);
    final hasMore = _hasMore[key]!;
    final loading = _isLoadingOlder[key]!;
    if (!hasMore.value || loading.value) return;

    loading.value = true;
    final failed = paginationFailedFor(roomId: roomId, parent: parent);
    failed.value = false;
    try {
      final page = await _paginationPort.loadOlder(
        roomId: roomId,
        parentEventId: parent.id,
        beforeReplyId: replies.value.isEmpty ? null : replies.value.first.id,
      );
      final existingIds = replies.value.map((reply) => reply.id).toSet();
      final uniqueOlder = page.replies
          .where((reply) => !existingIds.contains(reply.id))
          .toList(growable: false);
      if (uniqueOlder.isNotEmpty) {
        replies.value = List<ThreadReply>.unmodifiable(<ThreadReply>[
          ...uniqueOlder,
          ...replies.value,
        ]);
      }
      hasMore.value = page.hasMore;
    } catch (_) {
      failed.value = true;
    } finally {
      loading.value = false;
    }
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
    _runtimeThreadParentIds.add(parent.id);
    unawaited(_settle(roomId: roomId, parent: parent, reply: reply));
    return reply;
  }

  ThreadReply sendLocation({
    required String roomId,
    required TimelineMessage parent,
    required TimelineLocation location,
  }) {
    requireSupportedComposerAction(
      location.kind == TimelineLocationKind.liveLocation
          ? ThreadComposerAction.liveLocation
          : ThreadComposerAction.staticLocation,
    );
    final transactionId = 'kite-thread-${_transactionCounter++}';
    final reply = ThreadReply(
      id: transactionId,
      sender: 'You',
      body: '',
      mine: true,
      timeLabel: 'now',
      location: location,
      sendState: TimelineSendState.sending,
    );
    final replies = repliesFor(roomId: roomId, parent: parent);
    replies.value = List<ThreadReply>.unmodifiable(<ThreadReply>[
      ...replies.value,
      reply,
    ]);
    _runtimeThreadParentIds.add(parent.id);
    unawaited(_settleLocation(roomId: roomId, parent: parent, reply: reply));
    return reply;
  }

  ThreadReply sendAttachment({
    required String roomId,
    required TimelineMessage parent,
    required TimelineAttachment attachment,
    String caption = '',
  }) {
    final transactionId = 'kite-thread-${_transactionCounter++}';
    final reply = ThreadReply(
      id: transactionId,
      sender: 'You',
      body: caption.trim(),
      mine: true,
      timeLabel: 'now',
      attachment: attachment,
      sendState: TimelineSendState.sending,
    );
    final replies = repliesFor(roomId: roomId, parent: parent);
    replies.value = List<ThreadReply>.unmodifiable(<ThreadReply>[
      ...replies.value,
      reply,
    ]);
    _runtimeThreadParentIds.add(parent.id);
    unawaited(_settleAttachment(roomId: roomId, parent: parent, reply: reply));
    return reply;
  }

  void toggleAudioPlayback(ThreadReply reply) {
    final kind = reply.attachment?.kind;
    if (kind == null || !kind.isAudio) return;
    reply.audioPlaybackState.value =
        reply.audioPlaybackState.peek() == TimelineAudioPlaybackState.playing
        ? TimelineAudioPlaybackState.paused
        : TimelineAudioPlaybackState.playing;
  }

  void retryReply({
    required String roomId,
    required TimelineMessage parent,
    required ThreadReply reply,
  }) {
    if (reply.sendState.value != TimelineSendState.failed) return;
    reply.sendState.value = TimelineSendState.sending;
    if (reply.attachment != null) {
      unawaited(
        _settleAttachment(roomId: roomId, parent: parent, reply: reply),
      );
    } else if (reply.location != null) {
      unawaited(_settleLocation(roomId: roomId, parent: parent, reply: reply));
    } else {
      unawaited(_settle(roomId: roomId, parent: parent, reply: reply));
    }
  }

  void reset({
    ThreadSendPort? sendPort,
    ThreadAttachmentSendPort? attachmentSendPort,
    ThreadLocationPort? locationPort,
    ThreadPaginationPort? paginationPort,
    ThreadSubscriptionPort? subscriptionPort,
  }) {
    if (sendPort != null) _sendPort = sendPort;
    if (attachmentSendPort != null) _attachmentSendPort = attachmentSendPort;
    if (locationPort != null) _locationPort = locationPort;
    if (paginationPort != null) _paginationPort = paginationPort;
    if (subscriptionPort != null) _subscriptionPort = subscriptionPort;
    _transactionCounter = 0;
    _threads.clear();
    _hasMore.clear();
    _isLoadingOlder.clear();
    _paginationFailed.clear();
    _unreadCount.clear();
    _roomUnreadThreadCount.clear();
    _latestReadReplyId.clear();
    _focusedReplyId.clear();
    _isFollowing.clear();
    _isUpdatingSubscription.clear();
    _subscriptionFailed.clear();
    _runtimeThreadParentIds.clear();
  }

  Future<void> _settleLocation({
    required String roomId,
    required TimelineMessage parent,
    required ThreadReply reply,
  }) async {
    final location = reply.location;
    if (location == null) return;
    try {
      final outcome = await _locationPort.sendLocation(
        roomId: roomId,
        parentEventId: parent.id,
        transactionId: reply.id,
        location: location,
      );
      reply.sendState.value = switch (outcome) {
        TimelineSendOutcome.sent => TimelineSendState.sent,
        TimelineSendOutcome.failed => TimelineSendState.failed,
      };
    } catch (_) {
      reply.sendState.value = TimelineSendState.failed;
    }
  }

  Future<void> _settleAttachment({
    required String roomId,
    required TimelineMessage parent,
    required ThreadReply reply,
  }) async {
    final attachment = reply.attachment;
    if (attachment == null) return;
    try {
      final outcome = await _attachmentSendPort.sendAttachment(
        roomId: roomId,
        parentEventId: parent.id,
        transactionId: reply.id,
        attachment: attachment,
        caption: reply.body,
      );
      reply.sendState.value = switch (outcome) {
        TimelineSendOutcome.sent => TimelineSendState.sent,
        TimelineSendOutcome.failed => TimelineSendState.failed,
      };
    } catch (_) {
      reply.sendState.value = TimelineSendState.failed;
    }
  }

  Future<void> _settle({
    required String roomId,
    required TimelineMessage parent,
    required ThreadReply reply,
  }) async {
    try {
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
    } catch (_) {
      reply.sendState.value = TimelineSendState.failed;
    }
  }

  String _key(String roomId, String parentEventId) => '$roomId::$parentEventId';
}

final threadController = ThreadController();
