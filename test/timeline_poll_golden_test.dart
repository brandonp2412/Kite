import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_poll_card.dart';

void main() {
  Future<void> pumpPolls(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(860, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final active = TimelinePoll(
      question: 'Where should we have lunch?',
      options: const <TimelinePollOption>[
        TimelinePollOption(id: 'tacos', label: 'Tacos'),
        TimelinePollOption(id: 'sushi', label: 'Sushi'),
        TimelinePollOption(id: 'salad', label: 'Salad'),
      ],
      voteCounts: const <String, int>{'tacos': 5, 'sushi': 3, 'salad': 2},
      selectedOptionId: 'tacos',
    );
    final ended = TimelinePoll(
      question: 'Release channel?',
      options: const <TimelinePollOption>[
        TimelinePollOption(id: 'stable', label: 'Stable'),
        TimelinePollOption(id: 'beta', label: 'Beta'),
      ],
      voteCounts: const <String, int>{'stable': 8, 'beta': 4},
      selectedOptionId: 'stable',
      isEnded: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('poll-golden-surface'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TimelinePollCard(
                      messageId: 'active',
                      poll: active,
                      onVote: (_) {},
                    ),
                    const SizedBox(width: 20),
                    TimelinePollCard(
                      messageId: 'ended',
                      poll: ended,
                      onVote: (_) {},
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
  }

  testWidgets('timeline polls approved baseline - light', (tester) async {
    await pumpPolls(tester, themeMode: ThemeMode.light);
    await expectLater(
      find.byKey(const Key('poll-golden-surface')),
      matchesGoldenFile('goldens/timeline_polls_light.png'),
    );
  });

  testWidgets('timeline polls approved baseline - dark', (tester) async {
    await pumpPolls(tester, themeMode: ThemeMode.dark);
    await expectLater(
      find.byKey(const Key('poll-golden-surface')),
      matchesGoldenFile('goldens/timeline_polls_dark.png'),
    );
  });
}
