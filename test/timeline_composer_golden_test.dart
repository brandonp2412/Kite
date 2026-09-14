import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  for (final variant in <({String name, ThemeData theme})>[
    (name: 'light', theme: KiteTheme.light),
    (name: 'dark', theme: KiteTheme.dark),
  ]) {
    testWidgets('timeline and composer ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-composer-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_composer_${variant.name}.png'),
      );
    });

    testWidgets('message actions ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('message-action-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_actions_${variant.name}.png'),
      );
    });

    testWidgets('forward message ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-forward')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forward-room-bob')));
      await tester.pump();

      expect(find.byKey(const Key('forward-message-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_forward_${variant.name}.png'),
      );
    });

    testWidgets('report message ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(),
        moderationPort: DeterministicTimelineModerationPort(),
      );
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-report')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-message-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_report_${variant.name}.png'),
      );
    });

    testWidgets('reaction picker ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-more-reactions')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reaction-picker-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile(
          'goldens/timeline_reaction_picker_${variant.name}.png',
        ),
      );
    });

    testWidgets('reaction summary ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      final target = timelineController.messagesFor('alice').value[98];
      timelineController.toggleReaction(target, '👍', reactor: 'Alice');
      timelineController.toggleReaction(target, '👍');
      timelineController.toggleReaction(target, '🎉', reactor: 'Bob');
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-composer-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reaction-👍-alice-98')), findsOneWidget);
      expect(find.byKey(const Key('reaction-🎉-alice-98')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_reactions_${variant.name}.png'),
      );
    });

    testWidgets('delete confirmation ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-message-dialog')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_delete_${variant.name}.png'),
      );
    });

    testWidgets('redacted message ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      timelineController.redactText(
        timelineController.messagesFor('alice').value.last,
      );
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-composer-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Message deleted'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_redacted_${variant.name}.png'),
      );
    });

    testWidgets('reply composer ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-composer-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-action-reply')));
      await tester.pumpAndSettle();

      expect(find.text('Replying to Alice'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_reply_${variant.name}.png'),
      );
    });
  }
}
