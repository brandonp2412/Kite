import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      pollPort: DeterministicTimelinePollPort(),
    );
    selectRoom('kite');
  });

  test(
    'poll model validates choices and keeps vote mutations leaf-scoped',
    () async {
      final port = DeterministicTimelinePollPort(latency: Duration.zero);
      final controller = TimelineController(pollPort: port);

      expect(
        () => controller.sendPoll(
          'alice',
          question: 'Too few?',
          options: const <String>['Only one'],
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.sendPoll(
          'alice',
          question: 'Duplicates?',
          options: const <String>['Same', 'Same'],
        ),
        throwsArgumentError,
      );

      final message = controller.sendPoll(
        'alice',
        question: 'Lunch?',
        options: const <String>['Tacos', 'Sushi'],
      );
      final roomList = controller.messagesFor('alice').value;
      await Future<void>.delayed(Duration.zero);

      expect(message.sendState.value, TimelineSendState.sent);
      expect(message.transactionId, startsWith('kite-txn-'));
      expect(port.createdEventIds, <String>[message.transactionId!]);
      expect(await controller.votePoll('alice', message, 'option-0'), isTrue);
      expect(controller.messagesFor('alice').value, same(roomList));
      expect(message.poll?.selectedOptionId, 'option-0');
      expect(message.poll?.votesFor('option-0'), 1);

      expect(await controller.votePoll('alice', message, 'option-1'), isTrue);
      expect(message.poll?.votesFor('option-0'), 0);
      expect(message.poll?.votesFor('option-1'), 1);
      expect(await controller.endPoll('alice', message), isTrue);
      expect(message.poll?.isEnded, isTrue);
      expect(await controller.votePoll('alice', message, 'option-0'), isFalse);
    },
  );

  testWidgets('composer creates, votes, and ends a poll from the timeline', (
    tester,
  ) async {
    final port = DeterministicTimelinePollPort(latency: Duration.zero);
    timelineController.reset(pollPort: port);
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-poll')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poll-create-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('poll-question-field')),
      'Where should we eat?',
    );
    await tester.enterText(
      find.byKey(const Key('poll-option-field-0')),
      'Tacos',
    );
    await tester.enterText(
      find.byKey(const Key('poll-option-field-1')),
      'Sushi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('poll-create-confirm')));
    await tester.pumpAndSettle();

    final message = timelineController.messagesFor('alice').value.last;
    expect(find.byKey(Key('message-poll-${message.id}')), findsOneWidget);
    expect(find.text('Where should we eat?'), findsOneWidget);
    expect(message.sendState.value, TimelineSendState.sent);

    await tester.tap(find.byKey(Key('poll-option-${message.id}-option-0')));
    await tester.pumpAndSettle();
    expect(message.poll?.selectedOptionId, 'option-0');
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1 vote'), findsOneWidget);
    expect(port.votes.single.optionId, 'option-0');

    await tester.longPress(find.byKey(Key('message-poll-${message.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-end-poll')), findsOneWidget);
    expect(find.byKey(const Key('message-action-edit')), findsNothing);
    await tester.tap(find.byKey(const Key('message-action-end-poll')));
    await tester.pumpAndSettle();

    expect(message.poll?.isEnded, isTrue);
    expect(find.text('Final results'), findsOneWidget);
    expect(find.text('Ended'), findsOneWidget);
    expect(port.endedEventIds, <String>[message.id]);
  });
}
