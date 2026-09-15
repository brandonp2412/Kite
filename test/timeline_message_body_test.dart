import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_message_body.dart';

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}

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

  testWidgets('renderer styles composer inline formatting markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: const Scaffold(
          body: TimelineMessageBody(
            body: 'Use **bold**, *italic*, ~~retired~~, and `code`.',
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('timeline-body-paragraph')),
        matching: find.byType(RichText),
      ),
    );
    final spans = _textSpans(richText.text).toList(growable: false);
    final bold = spans.singleWhere((span) => span.text == 'bold');
    final italic = spans.singleWhere((span) => span.text == 'italic');
    final strike = spans.singleWhere((span) => span.text == 'retired');
    final code = spans.singleWhere((span) => span.text == 'code');

    expect(bold.style?.fontWeight, FontWeight.w700);
    expect(italic.style?.fontStyle, FontStyle.italic);
    expect(strike.style?.decoration, TextDecoration.lineThrough);
    expect(code.style?.fontFamily, 'monospace');
    expect(richText.text.toPlainText(), 'Use bold, italic, retired, and code.');
  });

  testWidgets('renderer gives user and room mentions explicit treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: const Scaffold(
          body: TimelineMessageBody(body: 'Ping @Alice in #Design-Lab now.'),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('timeline-body-paragraph')),
        matching: find.byType(RichText),
      ),
    );
    final spans = _textSpans(richText.text).toList(growable: false);
    final userMention = spans.singleWhere((span) => span.text == '@Alice');
    final roomMention = spans.singleWhere((span) => span.text == '#Design-Lab');

    expect(userMention.style?.fontWeight, FontWeight.w700);
    expect(roomMention.style?.fontWeight, FontWeight.w700);
    expect(userMention.style?.color, KiteTheme.light.colorScheme.primary);
    expect(roomMention.style?.color, KiteTheme.light.colorScheme.primary);
    expect(richText.text.toPlainText(), 'Ping @Alice in #Design-Lab now.');
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
