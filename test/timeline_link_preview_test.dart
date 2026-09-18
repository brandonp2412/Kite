import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
      linkOpenPort: DeterministicTimelineLinkOpenPort(),
    );
    selectRoom('kite');
  });

  test('preview extraction normalizes punctuation and path context', () {
    final preview = timelineLinkPreviewForText(
      'Read https://matrix.org/docs/client-server-api/, then reply.',
    );

    expect(preview, isNotNull);
    expect(
      preview!.uri.toString(),
      'https://matrix.org/docs/client-server-api/',
    );
    expect(preview.title, 'matrix.org');
    expect(preview.description, 'docs › client-server-api');
  });

  test('platform link port launches only external http links', () async {
    final opened = <Uri>[];
    final port = PlatformTimelineLinkOpenPort(
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await port.open(Uri.parse('https://matrix.org/docs'));
    await port.open(Uri.parse('matrix:roomid/room:example.org'));
    await port.open(Uri.parse('javascript:alert(1)'));

    expect(opened, <Uri>[Uri.parse('https://matrix.org/docs')]);
  });

  testWidgets('timeline link preview opens through the platform boundary', (
    tester,
  ) async {
    final port = DeterministicTimelineLinkOpenPort();
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
      linkOpenPort: port,
    );
    selectRoom('alice');
    final message = timelineController.sendText(
      'alice',
      'Element docs https://element.io/help',
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final preview = find.byKey(Key('message-link-preview-${message.id}'));
    expect(preview, findsOneWidget);
    expect(find.text('element.io'), findsOneWidget);
    expect(find.text('help'), findsOneWidget);

    final rect = tester.getRect(preview);
    await tester.tap(
      find.descendant(
        of: preview,
        matching: find.byKey(const Key('timeline-link-preview-open')),
      ),
    );
    await tester.pump();

    expect(port.opened, <Uri>[Uri.parse('https://element.io/help')]);
    expect(tester.getRect(preview), rect);
  });
}
