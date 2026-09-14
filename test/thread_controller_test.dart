import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

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
}
