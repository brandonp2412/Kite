// SPDX-FileCopyrightText: 2019-Present Contributors to Kite
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

Future<void> _pumpParentUpdates(
  WidgetTester tester,
  ValueNotifier<int> tick,
) async {
  for (var index = 0; index < 80; index++) {
    tick.value++;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unchanged bubble painter parent rebuild performance', (
    tester,
  ) async {
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
            width: 900,
            height: 820,
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
                          child: const SizedBox(width: 720, height: 32),
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

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['metadata'] = <String, dynamic>{
      'fixture': 'bubble_painter_parent_rebuild_v1',
      'surface': 'nox_linux',
      'painters': 24,
      'updates': 80,
    };

    await binding.watchPerformance(
      () => _pumpParentUpdates(tester, tick),
      reportKey: 'bubble_painter_parent_rebuild',
    );

    final measuredPaints = _CountingBubblePainter.paintCount;
    (binding.reportData!['metadata'] as Map<String, dynamic>)['paintCount'] =
        measuredPaints;

    final beforeColorChange = _CountingBubblePainter.paintCount;
    tick.value = -1;
    await tester.pump();
    expect(_CountingBubblePainter.paintCount, greaterThan(beforeColorChange));

    final beforeScroll = _CountingBubblePainter.paintCount;
    scrollController.jumpTo(16);
    await tester.pump();
    expect(_CountingBubblePainter.paintCount, greaterThan(beforeScroll));
  });
}
