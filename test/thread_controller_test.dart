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
