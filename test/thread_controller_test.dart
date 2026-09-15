import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _ControlledSubscriptionPort implements ThreadSubscriptionPort {
  final List<({String roomId, String parentEventId, bool following})> calls =
      <({String roomId, String parentEventId, bool following})>[];
  final List<Completer<ThreadSubscriptionOutcome>> attempts =
      <Completer<ThreadSubscriptionOutcome>>[];

  @override
  Future<ThreadSubscriptionOutcome> setFollowing({
    required String roomId,
    required String parentEventId,
    required bool following,
  }) {
    calls.add((
      roomId: roomId,
      parentEventId: parentEventId,
      following: following,
    ));
    final completer = Completer<ThreadSubscriptionOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

class _ControlledThreadAttachmentPort implements ThreadAttachmentSendPort {
  final List<
    ({
      String roomId,
      String parentEventId,
      String transactionId,
      TimelineAttachment attachment,
      String caption,
    })
  >
  calls =
      <
        ({
          String roomId,
          String parentEventId,
          String transactionId,
          TimelineAttachment attachment,
          String caption,
        })
      >[];
  final List<Completer<TimelineSendOutcome>> attempts =
      <Completer<TimelineSendOutcome>>[];

  @override
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  }) {
    calls.add((
      roomId: roomId,
      parentEventId: parentEventId,
      transactionId: transactionId,
      attachment: attachment,
      caption: caption,
    ));
    final completer = Completer<TimelineSendOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

class _ControlledThreadPort implements ThreadSendPort {
  final List<Completer<TimelineSendOutcome>> attempts =
      <Completer<TimelineSendOutcome>>[];

  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) {
    final completer = Completer<TimelineSendOutcome>();
    attempts.add(completer);
    return completer.future;
  }
}

class _ThrowingThreadPort implements ThreadSendPort {
  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) async {
    throw StateError('thread send failed');
  }
}

class _ThrowingThreadAttachmentPort implements ThreadAttachmentSendPort {
  @override
  Future<TimelineSendOutcome> sendAttachment({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required TimelineAttachment attachment,
    required String caption,
  }) async {
    throw StateError('thread attachment send failed');
  }
}

class _ThrowingSubscriptionPort implements ThreadSubscriptionPort {
  @override
  Future<ThreadSubscriptionOutcome> setFollowing({
    required String roomId,
    required String parentEventId,
    required bool following,
  }) async {
    throw StateError('thread subscription failed');
  }
}

class _FailOncePaginationPort implements ThreadPaginationPort {
  var calls = 0;

  @override
  Future<ThreadPage> loadOlder({
    required String roomId,
    required String parentEventId,
    required String? beforeReplyId,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('thread pagination failed');
    return ThreadPage(
      replies: <ThreadReply>[
        ThreadReply(
          id: '$parentEventId-recovered-older',
          sender: 'Alice',
          body: 'Recovered older context',
          mine: false,
          timeLabel: '09:30',
        ),
      ],
      hasMore: false,
    );
  }
}

void main() {
  test('deterministic thread summary seeds only supported parent events', () {
    final controller = ThreadController();
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    final plainParent = TimelineMessage(
      id: 'alice-99',
      sender: 'You',
      body: 'No thread',
      mine: true,
      timeLabel: '10:01',
    );

    expect(controller.hasThread(parent.id), isTrue);
    expect(controller.hasThread(plainParent.id), isFalse);
    expect(
      controller.repliesFor(roomId: 'alice', parent: parent).value,
      hasLength(3),
    );
    expect(
      controller.repliesFor(roomId: 'alice', parent: plainParent).value,
      isEmpty,
    );
  });

  test('thread unread state advances to the latest reply when marked read', () {
    final controller = ThreadController();
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    final replies = controller
        .repliesFor(roomId: 'alice', parent: parent)
        .value;

    expect(controller.unreadCountFor(roomId: 'alice', parent: parent).value, 2);
    expect(
      controller.latestReadReplyIdFor(roomId: 'alice', parent: parent).value,
      replies.first.id,
    );

    controller.markRead(roomId: 'alice', parent: parent);

    expect(controller.unreadCountFor(roomId: 'alice', parent: parent).value, 0);
    expect(
      controller.latestReadReplyIdFor(roomId: 'alice', parent: parent).value,
      replies.last.id,
    );
  });

  test('room thread unread aggregate reconciles when a thread is read', () {
    final controller = ThreadController();
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    controller.repliesFor(roomId: 'alice', parent: parent);
    controller.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 5,
    );

    expect(controller.unreadThreadCountForRoom('alice').value, 5);

    controller.markRead(roomId: 'alice', parent: parent);

    expect(controller.unreadThreadCountForRoom('alice').value, 3);
    expect(
      () => controller.updateRoomUnreadThreadCount(
        roomId: 'alice',
        unreadThreadCount: -1,
      ),
      throwsArgumentError,
    );
  });

  test('marking a room read clears every loaded thread unread state', () {
    final controller = ThreadController();
    final firstParent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'First parent',
      mine: false,
      timeLabel: '10:00',
    );
    final secondParent = TimelineMessage(
      id: 'alice-81',
      sender: 'Alice',
      body: 'Second parent',
      mine: false,
      timeLabel: '09:55',
    );
    final firstReplies = controller
        .repliesFor(roomId: 'alice', parent: firstParent)
        .value;
    final secondReplies = controller
        .repliesFor(roomId: 'alice', parent: secondParent)
        .value;
    controller.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 4,
    );

    controller.markRoomThreadsRead('alice');

    expect(
      controller.unreadCountFor(roomId: 'alice', parent: firstParent).value,
      0,
    );
    expect(
      controller.unreadCountFor(roomId: 'alice', parent: secondParent).value,
      0,
    );
    expect(controller.unreadThreadCountForRoom('alice').value, 0);
    expect(
      controller
          .latestReadReplyIdFor(roomId: 'alice', parent: firstParent)
          .value,
      firstReplies.last.id,
    );
    expect(
      controller
          .latestReadReplyIdFor(roomId: 'alice', parent: secondParent)
          .value,
      secondReplies.last.id,
    );
  });

  test('thread snapshot replaces cached replies without broad state loss', () {
    final controller = ThreadController();
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    final mediaReply = ThreadReply(
      id: 'alice-98-media',
      sender: 'Alice',
      body: 'Scoped media',
      mine: false,
      timeLabel: '10:04',
      attachment: const TimelineAttachment(
        id: 'thread-media',
        kind: TimelineAttachmentKind.image,
        name: 'thread.png',
        sizeLabel: '1.2 MB · Photo',
      ),
    );

    controller.applyThreadSnapshot(
      roomId: 'alice',
      parent: parent,
      replies: <ThreadReply>[mediaReply],
      hasMore: false,
      unreadCount: 1,
      latestReadReplyId: null,
    );

    expect(
      controller.repliesFor(roomId: 'alice', parent: parent).value,
      <ThreadReply>[mediaReply],
    );
    expect(
      controller.hasMoreFor(roomId: 'alice', parent: parent).value,
      isFalse,
    );
    expect(controller.unreadCountFor(roomId: 'alice', parent: parent).value, 1);
    expect(
      controller.latestReadReplyIdFor(roomId: 'alice', parent: parent).value,
      isNull,
    );
    expect(
      () => controller.applyThreadSnapshot(
        roomId: 'alice',
        parent: parent,
        replies: <ThreadReply>[mediaReply],
        hasMore: false,
        unreadCount: 2,
      ),
      throwsArgumentError,
    );
  });

  test('thread pagination prepends older replies exactly once', () async {
    final controller = ThreadController(
      paginationPort: const DeterministicThreadPaginationPort(
        latency: Duration.zero,
      ),
    );
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    final replies = controller.repliesFor(roomId: 'alice', parent: parent);
    final initialIds = replies.value.map((reply) => reply.id).toList();

    expect(
      controller.hasMoreFor(roomId: 'alice', parent: parent).value,
      isTrue,
    );
    await controller.loadOlder(roomId: 'alice', parent: parent);

    expect(replies.value, hasLength(initialIds.length + 2));
    expect(replies.value.first.id, 'alice-98-thread-older-0');
    expect(replies.value.skip(2).map((reply) => reply.id), initialIds);
    expect(
      controller.hasMoreFor(roomId: 'alice', parent: parent).value,
      isFalse,
    );

    await controller.loadOlder(roomId: 'alice', parent: parent);
    expect(replies.value, hasLength(initialIds.length + 2));
  });

  test(
    'thread pagination failure remains retryable and clears on success',
    () async {
      final port = _FailOncePaginationPort();
      final controller = ThreadController(paginationPort: port);
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final replies = controller.repliesFor(roomId: 'alice', parent: parent);
      final initialCount = replies.value.length;

      await controller.loadOlder(roomId: 'alice', parent: parent);

      expect(port.calls, 1);
      expect(replies.value, hasLength(initialCount));
      expect(
        controller.paginationFailedFor(roomId: 'alice', parent: parent).value,
        isTrue,
      );
      expect(
        controller.isLoadingOlderFor(roomId: 'alice', parent: parent).value,
        isFalse,
      );
      expect(
        controller.hasMoreFor(roomId: 'alice', parent: parent).value,
        isTrue,
      );

      await controller.loadOlder(roomId: 'alice', parent: parent);

      expect(port.calls, 2);
      expect(replies.value, hasLength(initialCount + 1));
      expect(replies.value.first.id, 'alice-98-recovered-older');
      expect(
        controller.paginationFailedFor(roomId: 'alice', parent: parent).value,
        isFalse,
      );
      expect(
        controller.hasMoreFor(roomId: 'alice', parent: parent).value,
        isFalse,
      );
    },
  );

  test(
    'focused reply lookup paginates older thread pages with a hard bound',
    () async {
      final controller = ThreadController(
        paginationPort: const DeterministicThreadPaginationPort(
          latency: Duration.zero,
        ),
      );
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );

      expect(
        controller
            .repliesFor(roomId: 'alice', parent: parent)
            .value
            .any((reply) => reply.id == 'alice-98-thread-older-0'),
        isFalse,
      );
      expect(
        await controller.ensureReplyAvailable(
          roomId: 'alice',
          parent: parent,
          replyId: 'alice-98-thread-older-0',
        ),
        isTrue,
      );
      expect(
        controller
            .repliesFor(roomId: 'alice', parent: parent)
            .value
            .any((reply) => reply.id == 'alice-98-thread-older-0'),
        isTrue,
      );
      expect(
        await controller.ensureReplyAvailable(
          roomId: 'alice',
          parent: parent,
          replyId: 'missing-reply',
          maxPages: 0,
        ),
        isFalse,
      );
      await expectLater(
        controller.ensureReplyAvailable(
          roomId: 'alice',
          parent: parent,
          replyId: 'missing-reply',
          maxPages: -1,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'failed thread reply retries without duplicating the local event',
    () async {
      final port = _ControlledThreadPort();
      final controller = ThreadController(sendPort: port);
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final replies = controller.repliesFor(roomId: 'alice', parent: parent);
      final initialCount = replies.value.length;

      final reply = controller.sendReply(
        roomId: 'alice',
        parent: parent,
        rawBody: 'Retry me',
      );
      port.attempts.single.complete(TimelineSendOutcome.failed);
      await Future<void>.delayed(Duration.zero);

      expect(reply.sendState.value, TimelineSendState.failed);
      controller.retryReply(roomId: 'alice', parent: parent, reply: reply);

      expect(reply.sendState.value, TimelineSendState.sending);
      expect(port.attempts, hasLength(2));
      expect(replies.value, hasLength(initialCount + 1));
      expect(replies.value.last, same(reply));

      port.attempts.last.complete(TimelineSendOutcome.sent);
      await Future<void>.delayed(Duration.zero);

      expect(reply.sendState.value, TimelineSendState.sent);
      expect(replies.value, hasLength(initialCount + 1));
    },
  );

  test(
    'thread attachment send and retry stay scoped without duplicate replies',
    () async {
      final port = _ControlledThreadAttachmentPort();
      final controller = ThreadController(attachmentSendPort: port);
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final replies = controller.repliesFor(roomId: 'alice', parent: parent);
      final initialCount = replies.value.length;
      const attachment = TimelineAttachment(
        id: 'thread-photo',
        kind: TimelineAttachmentKind.image,
        name: 'thread-photo.jpg',
        sizeLabel: '2.4 MB · Photo',
      );

      final reply = controller.sendAttachment(
        roomId: 'alice',
        parent: parent,
        attachment: attachment,
        caption: 'Scoped media',
      );

      expect(replies.value, hasLength(initialCount + 1));
      expect(replies.value.last, same(reply));
      expect(reply.attachment, same(attachment));
      expect(reply.body, 'Scoped media');
      expect(reply.sendState.value, TimelineSendState.sending);
      expect(port.calls.single.roomId, 'alice');
      expect(port.calls.single.parentEventId, parent.id);
      expect(port.calls.single.caption, 'Scoped media');

      port.attempts.single.complete(TimelineSendOutcome.failed);
      await Future<void>.delayed(Duration.zero);
      expect(reply.sendState.value, TimelineSendState.failed);

      controller.retryReply(roomId: 'alice', parent: parent, reply: reply);
      expect(port.attempts, hasLength(2));
      expect(replies.value, hasLength(initialCount + 1));

      port.attempts.last.complete(TimelineSendOutcome.sent);
      await Future<void>.delayed(Duration.zero);
      expect(reply.sendState.value, TimelineSendState.sent);
      expect(replies.value, hasLength(initialCount + 1));
    },
  );

  test(
    'thread reply stays scoped to its parent and settles through the port',
    () async {
      final port = _ControlledThreadPort();
      final controller = ThreadController(sendPort: port);
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final replies = controller.repliesFor(roomId: 'alice', parent: parent);
      final initialCount = replies.value.length;

      final reply = controller.sendReply(
        roomId: 'alice',
        parent: parent,
        rawBody: 'Scoped reply',
      );

      expect(replies.value, hasLength(initialCount + 1));
      expect(replies.value.last, same(reply));
      expect(reply.body, 'Scoped reply');
      expect(reply.sendState.value, TimelineSendState.sending);
      expect(port.attempts, hasLength(1));

      port.attempts.single.complete(TimelineSendOutcome.sent);
      await Future<void>.delayed(Duration.zero);

      expect(reply.sendState.value, TimelineSendState.sent);
    },
  );
  test(
    'thrown send failures settle text and media replies as retryable',
    () async {
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final controller = ThreadController(
        sendPort: _ThrowingThreadPort(),
        attachmentSendPort: _ThrowingThreadAttachmentPort(),
      );

      final textReply = controller.sendReply(
        roomId: 'alice',
        parent: parent,
        rawBody: 'Retryable text',
      );
      final mediaReply = controller.sendAttachment(
        roomId: 'alice',
        parent: parent,
        attachment: const TimelineAttachment(
          id: 'thread-photo',
          kind: TimelineAttachmentKind.image,
          name: 'thread-photo.jpg',
          sizeLabel: '2.4 MB · Photo',
        ),
        caption: 'Retryable media',
      );

      await Future<void>.delayed(Duration.zero);

      expect(textReply.sendState.value, TimelineSendState.failed);
      expect(mediaReply.sendState.value, TimelineSendState.failed);
    },
  );

  test('thread notification subscription is scoped and failure-safe', () async {
    final port = _ControlledSubscriptionPort();
    final controller = ThreadController(subscriptionPort: port);
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );
    final otherParent = TimelineMessage(
      id: 'alice-81',
      sender: 'Alice',
      body: 'Other parent',
      mine: false,
      timeLabel: '09:55',
    );

    final following = controller.isFollowingFor(
      roomId: 'alice',
      parent: parent,
    );
    expect(following.value, isFalse);
    expect(
      controller.isFollowingFor(roomId: 'alice', parent: otherParent).value,
      isFalse,
    );

    final firstToggle = controller.toggleFollowing(
      roomId: 'alice',
      parent: parent,
    );
    expect(
      controller
          .isUpdatingSubscriptionFor(roomId: 'alice', parent: parent)
          .value,
      isTrue,
    );
    expect(port.calls.single.following, isTrue);
    port.attempts.single.complete(ThreadSubscriptionOutcome.applied);
    await firstToggle;

    expect(following.value, isTrue);
    expect(
      controller
          .isUpdatingSubscriptionFor(roomId: 'alice', parent: parent)
          .value,
      isFalse,
    );
    expect(
      controller.subscriptionFailedFor(roomId: 'alice', parent: parent).value,
      isFalse,
    );
    expect(
      controller.isFollowingFor(roomId: 'alice', parent: otherParent).value,
      isFalse,
    );

    final failedToggle = controller.toggleFollowing(
      roomId: 'alice',
      parent: parent,
    );
    port.attempts.last.complete(ThreadSubscriptionOutcome.failed);
    await failedToggle;

    expect(following.value, isTrue);
    expect(
      controller.subscriptionFailedFor(roomId: 'alice', parent: parent).value,
      isTrue,
    );
  });

  test('thrown subscription failures expose the retry state', () async {
    final controller = ThreadController(
      subscriptionPort: _ThrowingSubscriptionPort(),
    );
    final parent = TimelineMessage(
      id: 'alice-98',
      sender: 'Alice',
      body: 'Parent message',
      mine: false,
      timeLabel: '10:00',
    );

    await controller.toggleFollowing(roomId: 'alice', parent: parent);

    expect(
      controller.subscriptionFailedFor(roomId: 'alice', parent: parent).value,
      isTrue,
    );
    expect(
      controller
          .isUpdatingSubscriptionFor(roomId: 'alice', parent: parent)
          .value,
      isFalse,
    );
    expect(
      controller.isFollowingFor(roomId: 'alice', parent: parent).value,
      isFalse,
    );
  });

  test('thread composer boundary rejects live-location sharing', () {
    final controller = ThreadController();

    expect(
      controller.supportsComposerAction(ThreadComposerAction.text),
      isTrue,
    );
    expect(
      controller.supportsComposerAction(ThreadComposerAction.staticLocation),
      isTrue,
    );
    expect(
      controller.supportsComposerAction(ThreadComposerAction.liveLocation),
      isFalse,
    );
    expect(
      () => controller.requireSupportedComposerAction(
        ThreadComposerAction.liveLocation,
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'focused reply remains scoped to one thread and clears conditionally',
    () {
      final controller = ThreadController();
      final parent = TimelineMessage(
        id: 'alice-98',
        sender: 'Alice',
        body: 'Parent message',
        mine: false,
        timeLabel: '10:00',
      );
      final otherParent = TimelineMessage(
        id: 'alice-81',
        sender: 'Alice',
        body: 'Other parent',
        mine: false,
        timeLabel: '09:55',
      );

      controller.focusReply(
        roomId: 'alice',
        parent: parent,
        replyId: 'alice-98-thread-2',
      );

      expect(
        controller.focusedReplyIdFor(roomId: 'alice', parent: parent).value,
        'alice-98-thread-2',
      );
      expect(
        controller
            .focusedReplyIdFor(roomId: 'alice', parent: otherParent)
            .value,
        isNull,
      );

      controller.clearFocus(
        roomId: 'alice',
        parent: parent,
        onlyIfReplyId: 'wrong-id',
      );
      expect(
        controller.focusedReplyIdFor(roomId: 'alice', parent: parent).value,
        'alice-98-thread-2',
      );

      controller.clearFocus(
        roomId: 'alice',
        parent: parent,
        onlyIfReplyId: 'alice-98-thread-2',
      );
      expect(
        controller.focusedReplyIdFor(roomId: 'alice', parent: parent).value,
        isNull,
      );
    },
  );
}
