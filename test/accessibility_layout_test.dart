import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  setUp(() {
    threadController.reset();
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets(
    'room rows expose one actionable TalkBack node with useful text',
    (tester) async {
      await setViewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byKey(const Key('room-alice')));
      final data = node.getSemanticsData();
      expect(data.label, contains('Alice'));
      expect(data.label, contains('Deterministic direct message'));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    },
  );

  for (final entry in <String, Size>{
    'phone portrait': const Size(390, 844),
    'phone landscape': const Size(844, 390),
    'tablet': const Size(800, 1280),
    'desktop': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key} survives 200% text scaling without exceptions', (
      tester,
    ) async {
      await setViewport(tester, entry.value);
      selectRoom('alice');

      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: entry.value,
              textScaler: const TextScaler.linear(2),
            ),
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('sidebar')), findsOneWidget);

      if (entry.value.shortestSide < HomeScreen.phoneBreakpoint) {
        await tester.tap(find.byKey(const Key('room-alice')));
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('chat-panel')), findsOneWidget);
      expect(find.byKey(const Key('composer-attach')), findsOneWidget);
      expect(find.byKey(const Key('composer-send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selection and unread state have non-colour visual cues', (
    tester,
  ) async {
    await setViewport(tester, const Size(1200, 800));
    selectRoom('alice');
    threadController.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 2,
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final selectedTitle = tester.widget<Text>(
      find.byKey(const Key('room-title-alice')),
    );
    final unselectedTitle = tester.widget<Text>(
      find.byKey(const Key('room-title-bob')),
    );
    expect(selectedTitle.style?.fontWeight, FontWeight.w700);
    expect(unselectedTitle.style?.fontWeight, isNot(FontWeight.w700));
    expect(find.byKey(const Key('room-thread-unread-alice')), findsOneWidget);

    final selectedSemantics = tester.getSemantics(
      find.byKey(const Key('room-alice')),
    );
    expect(
      selectedSemantics.getSemanticsData().hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
  });

  testWidgets('failed sends use an error icon and retry semantics', (
    tester,
  ) async {
    await setViewport(tester, const Size(1200, 800));
    selectRoom('alice');
    final message = timelineController.sendText(
      'alice',
      '[deterministic-fail-once]',
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pump(const Duration(milliseconds: 220));

    expect(message.sendState.value, TimelineSendState.failed);
    expect(find.byKey(Key('retry-${message.id}')), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
  });

  testWidgets('composer actions meet the 48dp minimum touch target', (
    tester,
  ) async {
    await setViewport(tester, const Size(1200, 800));
    selectRoom('alice');

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    for (final key in <Key>[
      const Key('composer-attach'),
      const Key('composer-send'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
