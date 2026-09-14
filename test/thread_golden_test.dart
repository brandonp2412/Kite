import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    threadController.reset(sendPort: const DeterministicThreadSendPort());
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  for (final variant in <({String name, ThemeData theme})>[
    (name: 'light', theme: KiteTheme.light),
    (name: 'dark', theme: KiteTheme.dark),
  ]) {
    testWidgets('thread ${variant.name} reference render', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      threadController.reset(sendPort: const DeterministicThreadSendPort());
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
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thread-panel')), findsOneWidget);
      expect(find.text('3 replies'), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/thread_${variant.name}.png'),
      );
    });

    testWidgets('thread room unread ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      threadController.reset(sendPort: const DeterministicThreadSendPort());
      threadController.updateRoomUnreadThreadCount(
        roomId: 'alice',
        unreadThreadCount: 2,
      );
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

      expect(find.byKey(const Key('room-thread-unread-alice')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/thread_room_unread_${variant.name}.png'),
      );
    });
  }
}
