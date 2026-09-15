import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  testWidgets('composer previews, captions, and sends deterministic media', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-picker-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('attachment-option-photo-library')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-attachment-preview')),
      findsOneWidget,
    );
    expect(find.text('IMG_2048.jpg'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Screenshot from the latest build',
    );
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.attachment?.kind, TimelineAttachmentKind.image);
    expect(message.attachment?.name, 'IMG_2048.jpg');
    expect(message.body, 'Screenshot from the latest build');
    expect(find.byKey(const Key('composer-attachment-preview')), findsNothing);
    expect(find.byKey(Key('message-attachment-${message.id}')), findsOneWidget);
    expect(find.text('Screenshot from the latest build'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(message.sendState.value, TimelineSendState.sent);
  });

  testWidgets('attachment preview can be removed without sending', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    final initialCount = timelineController.messagesFor('alice').value.length;

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-document-file')));
    await tester.pumpAndSettle();
    expect(find.text('project-notes.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-attachment-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachment-preview')), findsNothing);
    expect(
      timelineController.messagesFor('alice').value,
      hasLength(initialCount),
    );
  });
}
