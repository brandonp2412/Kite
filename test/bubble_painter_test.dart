// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/pages/chat/events/message.dart';

class _CountingBubblePainter extends BubblePainter {
  _CountingBubblePainter({
    required super.context,
    required super.colors,
    required super.repaint,
  });

  static int paintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintCount++;
    super.paint(canvas, size);
  }
}

void main() {
  testWidgets(
    'BubblePainter skips unchanged rebuilds and repaints real changes',
    (tester) async {
      final tick = ValueNotifier<int>(0);
      final scrollController = ScrollController();
      addTearDown(tick.dispose);
      addTearDown(scrollController.dispose);

      const primaryColors = <Color>[Colors.blue, Colors.purple];
      const alternateColors = <Color>[Colors.orange, Colors.green];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, value, _) => SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      for (var index = 0; index < 24; index++)
                        Builder(
                          builder: (bubbleContext) => CustomPaint(
                            painter: _CountingBubblePainter(
                              context: bubbleContext,
                              colors: value == -1
                                  ? alternateColors
                                  : primaryColors,
                              repaint: scrollController,
                            ),
                            child: const SizedBox(width: 300, height: 32),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _CountingBubblePainter.paintCount = 0;

      tick.value++;
      await tester.pump();
      expect(_CountingBubblePainter.paintCount, 0);

      tick.value = -1;
      await tester.pump();
      expect(_CountingBubblePainter.paintCount, greaterThan(0));

      final beforeScroll = _CountingBubblePainter.paintCount;
      scrollController.jumpTo(16);
      await tester.pump();
      expect(_CountingBubblePainter.paintCount, greaterThan(beforeScroll));
    },
  );
}
