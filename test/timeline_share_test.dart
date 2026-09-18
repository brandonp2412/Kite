import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_share.dart';

void main() {
  test(
    'platform share port includes the visible body and exact event permalink',
    () async {
      final shared = <String>[];
      final port = PlatformTimelineSharePort(
        launcher: (text) async {
          shared.add(text);
        },
      );

      await port.shareMessage(
        const TimelineShareRequest(
          roomId: '!room:example.org',
          eventId: r'$event:example.org',
          body: 'Hello from Kite',
        ),
      );

      expect(shared, <String>[
        'Hello from Kite\n\n'
            'https://matrix.to/#/!room%3Aexample.org/%24event%3Aexample.org',
      ]);
    },
  );

  test('platform share port falls back to attachment name', () async {
    final shared = <String>[];
    final port = PlatformTimelineSharePort(
      launcher: (text) async {
        shared.add(text);
      },
    );

    await port.shareMessage(
      const TimelineShareRequest(
        roomId: '!room:example.org',
        eventId: r'$image:example.org',
        body: '',
        attachment: TimelineAttachment(
          id: 'mxc://example.org/image',
          kind: TimelineAttachmentKind.image,
          name: 'Sunset.jpg',
          sizeLabel: '2.0 MB · Image',
        ),
      ),
    );

    expect(shared.single, startsWith('Sunset.jpg\n\nhttps://matrix.to/#/'));
  });
}
