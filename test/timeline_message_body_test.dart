import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_message_body.dart';

void main() {
  test('parser preserves paragraphs, quotes, fenced code, and language', () {
    final blocks = TimelineBodyParser.parse(
      'Ship `stable` text.\n\n> Keep the anchor fixed.\n> No jitter.\n\n```dart\nfinal ready = true;\n```',
    );

    expect(blocks, hasLength(3));
    expect(blocks[0].type, TimelineBodyBlockType.paragraph);
    expect(blocks[0].text, 'Ship `stable` text.');
    expect(blocks[1].type, TimelineBodyBlockType.quote);
    expect(blocks[1].text, 'Keep the anchor fixed.\nNo jitter.');
    expect(blocks[2].type, TimelineBodyBlockType.code);
    expect(blocks[2].language, 'dart');
    expect(blocks[2].text, 'final ready = true;');
  });

  testWidgets('renderer exposes polished quote and code surfaces', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: TimelineMessageBody(
              body: 'Use `leaf signals` for updates.\n\n> Geometry stays fixed.\n\n```dart\nsignal.value = next;\n```',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('timeline-body-paragraph')), findsOneWidget);
    expect(find.byKey(const Key('timeline-body-quote')), findsOneWidget);
    expect(find.byKey(const Key('timeline-body-code')), findsOneWidget);
    expect(
      find.byKey(const Key('timeline-body-code-language')),
      findsOneWidget,
    );
    expect(find.text('signal.value = next;'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renderer detects RTL paragraph direction without affecting code',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: const Scaffold(
            body: TimelineMessageBody(body: 'مرحبا بالعالم'),
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const Key('timeline-body-paragraph')),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.textDirection, TextDirection.rtl);
    },
  );
}
