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

    testWidgets('read receipts ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      final target = timelineController.messagesFor('alice').value.last;
      timelineController.updateReadReceipts('alice', target.id, const <String>[
        'Alice',
        'Maya',
        'Sam',
      ]);
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-receipts-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('timeline-receipts-golden')),
        matchesGoldenFile('goldens/timeline_receipts_${variant.name}.png'),
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

    testWidgets('mention autocomplete ${variant.name} reference render', (
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
            key: Key('timeline-autocomplete-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('composer-field')), '@a');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('composer-autocomplete')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-autocomplete-golden')),
        matchesGoldenFile('goldens/timeline_autocomplete_${variant.name}.png'),
      );
    });

    testWidgets('formatting toolbar ${variant.name} reference render', (
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
            key: Key('timeline-formatting-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('composer-format-toggle')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('composer-formatting-toolbar')),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(const Key('timeline-formatting-golden')),
        matchesGoldenFile('goldens/timeline_formatting_${variant.name}.png'),
      );
    });

    testWidgets('formatted message ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      timelineController.sendText(
        'alice',
        'Use `leaf signals` for updates.\n\n> Geometry stays fixed.\n\n```dart\nsignal.value = next;\n```',
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

      expect(find.byKey(const Key('timeline-body-quote')), findsOneWidget);
      expect(find.byKey(const Key('timeline-body-code')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-composer-golden')),
        matchesGoldenFile('goldens/timeline_formatted_${variant.name}.png'),
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

    testWidgets('forward sheet ${variant.name} reference render', (
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

      expect(find.byKey(const Key('forward-message-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_forward_${variant.name}.png'),
      );
    });

    testWidgets('report sheet ${variant.name} reference render', (
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
      await tester.tap(find.byKey(const Key('message-action-report')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-message-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_report_${variant.name}.png'),
      );
    });

    testWidgets('composer emoji picker ${variant.name} reference render', (
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
      await tester.tap(find.byKey(const Key('composer-emoji')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('composer-emoji-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_emoji_${variant.name}.png'),
      );
    });

    testWidgets('unread marker ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      final messages = timelineController.messagesFor('alice').value;
      timelineController.setUnreadMarker(
        'alice',
        messages[messages.length - 3].id,
      );
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const RepaintBoundary(
            key: Key('timeline-unread-golden'),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('timeline-unread-marker')), findsOneWidget);
      expect(find.byKey(const Key('jump-to-unread')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('timeline-unread-golden')),
        matchesGoldenFile('goldens/timeline_unread_${variant.name}.png'),
      );
    });

    testWidgets('edit history ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      final target = timelineController.messagesFor('alice').value.last;
      timelineController.editText(target, 'Edited message 100 in Alice');
      selectRoom('alice');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: variant.theme,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edited-alice-99')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit-history-sheet')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/timeline_edit_history_${variant.name}.png'),
      );
    });
  }
}
