import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/threads/thread_view.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class _AlwaysFailThreadPort implements ThreadSendPort {
  const _AlwaysFailThreadPort();

  @override
  Future<TimelineSendOutcome> sendReply({
    required String roomId,
    required String parentEventId,
    required String transactionId,
    required String body,
  }) async => TimelineSendOutcome.failed;
}

void main() {
  tearDown(() {
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(),
      subscriptionPort: const DeterministicThreadSubscriptionPort(),
    );
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

    testWidgets('thread following ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      threadController.reset(
        sendPort: const DeterministicThreadSendPort(),
        subscriptionPort: const DeterministicThreadSubscriptionPort(
          latency: Duration.zero,
        ),
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
      await tester.tap(find.byKey(const Key('thread-summary-alice-98')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-subscription-toggle')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-subscription-following')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/thread_following_${variant.name}.png'),
      );
    });

    testWidgets('thread retry ${variant.name} reference render', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      threadController.reset(sendPort: const _AlwaysFailThreadPort());
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
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final reply = threadController.sendReply(
        roomId: 'alice',
        parent: parent,
        rawBody: 'Could not send — tap to retry',
      );
      await tester.pumpAndSettle();

      expect(reply.sendState.value, TimelineSendState.failed);
      expect(find.byKey(Key('thread-retry-${reply.id}')), findsOneWidget);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/thread_retry_${variant.name}.png'),
      );
    });

    testWidgets('thread focused ${variant.name} reference render', (
      tester,
    ) async {
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
      final parent = timelineController
          .messagesFor('alice')
          .value
          .firstWhere((message) => message.id == 'alice-98');
      final destination = AppDestination.thread(
        accountId: '@alice:kite.test',
        roomId: 'alice',
        eventId: 'alice-98-thread-2',
        threadRootEventId: 'alice-98',
      );
      final navigatorContext = tester.element(
        find.byKey(const Key('chat-panel')),
      );
      Navigator.of(navigatorContext).push(
        ThreadRoute.fromDestination(
          destination: destination,
          parent: parent,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-focused-alice-98-thread-2')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/thread_focus_${variant.name}.png'),
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
