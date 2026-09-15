import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  test('edits retain ordered prior bodies in leaf event state', () {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
    final message = controller.messagesFor('alice').value.last;
    final messageList = controller.messagesFor('alice').value;
    final historySignal = message.editHistoryState;
    final original = message.body;

    controller.editText(message, 'First edit');
    controller.editText(message, 'Second edit');

    expect(message.body, 'Second edit');
    expect(message.edited, isTrue);
    expect(message.editHistoryState, same(historySignal));
    expect(message.editHistory, <String>[original, 'First edit']);
    expect(controller.messagesFor('alice').value, same(messageList));
  });

  test('redaction clears edit history with the rest of event content', () {
    final controller = TimelineController(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
    final message = controller.messagesFor('alice').value.last;

    controller.editText(message, 'Edited once');
    expect(message.editHistory, isNotEmpty);

    controller.redactText(message);

    expect(message.body, isEmpty);
    expect(message.editHistory, isEmpty);
    expect(message.edited, isFalse);
    expect(message.redacted, isTrue);
  });
}
