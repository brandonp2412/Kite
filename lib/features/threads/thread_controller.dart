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
  });

  final Duration latency;

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
      replies: <ThreadReply>[
        ThreadReply(
          id: '$parentEventId-thread-older-0',
          sender: 'Mina',
          body: 'I added the earlier context here.',
          mine: false,
          timeLabel: '09:58',
        ),
        ThreadReply(
          id: '$parentEventId-thread-older-1',
          sender: 'You',
          body: 'Thanks — that fills in the missing part.',
          mine: true,
          timeLabel: '10:02',
        ),
      ],
      hasMore: false,
    );
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
  ThreadController({
    ThreadSendPort? sendPort,
    ThreadPaginationPort? paginationPort,
  }) : _sendPort = sendPort ?? const DeterministicThreadSendPort(),
       _paginationPort =
           paginationPort ?? const DeterministicThreadPaginationPort();

  ThreadSendPort _sendPort;
  ThreadPaginationPort _paginationPort;
  final Map<String, Signal<List<ThreadReply>>> _threads =
      <String, Signal<List<ThreadReply>>>{};
  final Map<String, Signal<bool>> _hasMore = <String, Signal<bool>>{};
  final Map<String, Signal<bool>> _isLoadingOlder = <String, Signal<bool>>{};
  final Map<String, Signal<int>> _unreadCount = <String, Signal<int>>{};
  final Map<String, Signal<String?>> _latestReadReplyId =
      <String, Signal<String?>>{};
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
      _unreadCount.putIfAbsent(key, () => signal(2));
      _latestReadReplyId.putIfAbsent(key, () => signal(replies.first.id));
      return signal(replies);
    });
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

  Signal<int> unreadCountFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _unreadCount[_key(roomId, parent.id)] ?? signal(0);
  }

  Signal<String?> latestReadReplyIdFor({
    required String roomId,
    required TimelineMessage parent,
  }) {
    repliesFor(roomId: roomId, parent: parent);
    return _latestReadReplyId[_key(roomId, parent.id)] ?? signal(null);
  }

  void markRead({required String roomId, required TimelineMessage parent}) {
    final replies = repliesFor(roomId: roomId, parent: parent).value;
    final key = _key(roomId, parent.id);
    _unreadCount[key]?.value = 0;
    _latestReadReplyId[key]?.value = replies.isEmpty ? null : replies.last.id;
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
    unawaited(_settle(roomId: roomId, parent: parent, reply: reply));
    return reply;
  }

  void reset({ThreadSendPort? sendPort, ThreadPaginationPort? paginationPort}) {
    if (sendPort != null) _sendPort = sendPort;
    if (paginationPort != null) _paginationPort = paginationPort;
    _transactionCounter = 0;
    _threads.clear();
    _hasMore.clear();
    _isLoadingOlder.clear();
    _unreadCount.clear();
    _latestReadReplyId.clear();
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
