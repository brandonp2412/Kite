import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';

enum TimelineBodyBlockType { paragraph, quote, code }

@immutable
class TimelineBodyBlock {
  const TimelineBodyBlock({
    required this.type,
    required this.text,
    this.language,
  });

  final TimelineBodyBlockType type;
  final String text;
  final String? language;
}

abstract final class TimelineBodyParser {
  static List<TimelineBodyBlock> parse(String body) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final blocks = <TimelineBodyBlock>[];
    var index = 0;

    while (index < lines.length) {
      if (lines[index].trim().isEmpty) {
        index += 1;
        continue;
      }

      final trimmed = lines[index].trimLeft();
      if (trimmed.startsWith('```')) {
        final language = trimmed.substring(3).trim();
        final code = <String>[];
        index += 1;
        while (index < lines.length &&
            !lines[index].trimLeft().startsWith('```')) {
          code.add(lines[index]);
          index += 1;
        }
        if (index < lines.length) index += 1;
        blocks.add(
          TimelineBodyBlock(
            type: TimelineBodyBlockType.code,
            text: code.join('\n'),
            language: language.isEmpty ? null : language,
          ),
        );
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quote = <String>[];
        while (index < lines.length) {
          final candidate = lines[index].trimLeft();
          if (!candidate.startsWith('>')) break;
          var content = candidate.substring(1);
          if (content.startsWith(' ')) content = content.substring(1);
          quote.add(content);
          index += 1;
        }
        blocks.add(
          TimelineBodyBlock(
            type: TimelineBodyBlockType.quote,
            text: quote.join('\n'),
          ),
        );
        continue;
      }

      final paragraph = <String>[];
      while (index < lines.length) {
        final candidate = lines[index];
        final candidateTrimmed = candidate.trimLeft();
        if (candidate.trim().isEmpty ||
            candidateTrimmed.startsWith('>') ||
            candidateTrimmed.startsWith('```')) {
          break;
        }
        paragraph.add(candidate);
        index += 1;
      }
      blocks.add(
        TimelineBodyBlock(
          type: TimelineBodyBlockType.paragraph,
          text: paragraph.join('\n'),
        ),
      );
    }

    return List<TimelineBodyBlock>.unmodifiable(blocks);
  }
}

class TimelineMessageBody extends StatelessWidget {
  const TimelineMessageBody({super.key, required this.body, this.textKey});

  final String body;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final blocks = TimelineBodyParser.parse(body);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < blocks.length; index++) ...<Widget>[
          _TimelineBodyBlockView(
            block: blocks[index],
            textKey: index == 0 ? textKey : null,
          ),
          if (index != blocks.length - 1)
            const SizedBox(height: KiteSpacing.xs),
        ],
      ],
    );
  }
}

class _TimelineBodyBlockView extends StatelessWidget {
  const _TimelineBodyBlockView({required this.block, this.textKey});

  final TimelineBodyBlock block;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (block.type) {
      TimelineBodyBlockType.paragraph => Text.rich(
        TextSpan(children: _inlineSpans(block.text, context)),
        key: textKey ?? const Key('timeline-body-paragraph'),
        style: KiteTypography.body.copyWith(color: colors.onSurface),
        textDirection: _directionFor(block.text),
      ),
      TimelineBodyBlockType.quote => Container(
        key: const Key('timeline-body-quote'),
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.sm,
          KiteSpacing.xs,
          KiteSpacing.sm,
          KiteSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          border: Border(
            left: BorderSide(color: colors.primary, width: KiteStroke.emphasis),
          ),
        ),
        child: Text.rich(
          TextSpan(children: _inlineSpans(block.text, context)),
          style: KiteTypography.body.copyWith(color: colors.onSurface),
          textDirection: _directionFor(block.text),
        ),
      ),
      TimelineBodyBlockType.code => Container(
        key: const Key('timeline-body-code'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (block.language != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.sm,
                    KiteSpacing.xs,
                    KiteSpacing.sm,
                    0,
                  ),
                  child: Text(
                    block.language!,
                    key: const Key('timeline-body-code-language'),
                    style: KiteTypography.metadata.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(KiteSpacing.sm),
                child: Text(
                  block.text,
                  style: KiteTypography.body.copyWith(
                    color: colors.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    };
  }

  static List<InlineSpan> _inlineSpans(String text, BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var cursor = 0;

    while (cursor < text.length) {
      final token = _nextInlineToken(text, cursor);
      if (token == null) {
        _appendPlainSpans(spans, text.substring(cursor), colors);
        break;
      }
      if (token.open > cursor) {
        _appendPlainSpans(spans, text.substring(cursor, token.open), colors);
      }
      final contentStart = token.open + token.marker.length;
      final close = text.indexOf(token.marker, contentStart);
      if (close < 0) {
        _appendPlainSpans(spans, text.substring(token.open), colors);
        break;
      }
      spans.add(
        TextSpan(
          text: text.substring(contentStart, close),
          style: switch (token.marker) {
            '`' => KiteTypography.body.copyWith(
              color: colors.onSurface,
              fontFamily: 'monospace',
              fontSize: 14,
              backgroundColor: colors.surfaceContainerLow,
            ),
            '**' => KiteTypography.body.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
            '*' => KiteTypography.body.copyWith(
              color: colors.onSurface,
              fontStyle: FontStyle.italic,
            ),
            '~~' => KiteTypography.body.copyWith(
              color: colors.onSurface,
              decoration: TextDecoration.lineThrough,
            ),
            _ => KiteTypography.body.copyWith(color: colors.onSurface),
          },
        ),
      );
      cursor = close + token.marker.length;
    }

    return spans;
  }

  static void _appendPlainSpans(
    List<InlineSpan> spans,
    String text,
    ColorScheme colors,
  ) {
    if (text.isEmpty) return;
    final pattern = RegExp(r'(^|\s)([@#][A-Za-z0-9_-]+)');
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      final leading = match.group(1)!;
      final token = match.group(2)!;
      final tokenStart = match.start + leading.length;
      if (tokenStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, tokenStart)));
      }
      spans.add(
        TextSpan(
          text: token,
          style: KiteTypography.body.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
            backgroundColor: colors.primaryContainer.withValues(alpha: 0.42),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
  }

  static ({int open, String marker})? _nextInlineToken(
    String text,
    int cursor,
  ) {
    ({int open, String marker})? next;
    for (final marker in const <String>['`', '**', '~~', '*']) {
      var open = text.indexOf(marker, cursor);
      if (marker == '*') {
        while (open >= 0 && text.startsWith('**', open)) {
          open = text.indexOf(marker, open + 2);
        }
      }
      if (open < 0) continue;
      final candidate = (open: open, marker: marker);
      if (next == null ||
          candidate.open < next.open ||
          (candidate.open == next.open &&
              candidate.marker.length > next.marker.length)) {
        next = candidate;
      }
    }
    return next;
  }

  static TextDirection? _directionFor(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0590 && rune <= 0x08FF) ||
          (rune >= 0xFB1D && rune <= 0xFEFC)) {
        return TextDirection.rtl;
      }
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return null;
  }
}
