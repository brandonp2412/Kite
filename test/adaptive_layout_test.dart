import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/home_screen.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    selectRoom('kite');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
  }

  for (final entry in <String, Size>{
    'portrait': const Size(390, 844),
    'landscape': const Size(844, 390),
  }.entries) {
    testWidgets('phone ${entry.key} uses single-pane navigation', (
      tester,
    ) async {
      await pumpAt(tester, entry.value);

      expect(find.text('Chats'), findsOneWidget);
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.byKey(const Key('chat-panel')), findsNothing);

      await tester.tap(find.byKey(const Key('room-alice')));
      await tester.pumpAndSettle();

      expect(selectedRoomId.value, 'alice');
      expect(find.byKey(const Key('sidebar')), findsNothing);
      expect(find.byKey(const Key('chat-panel')), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
    });
  }

  for (final entry in <String, Size>{
    'tablet': const Size(800, 1280),
    'desktop': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key} uses stable split-pane layout', (tester) async {
      await pumpAt(tester, entry.value);

      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.byKey(const Key('chat-panel')), findsOneWidget);

      final sidebar = tester.getSize(find.byKey(const Key('sidebar')));
      final expectedWidth = entry.key == 'tablet'
          ? HomeScreen.tabletSidebarWidth
          : HomeScreen.sidebarWidth;
      expect(sidebar.width, expectedWidth);

      await tester.tap(find.byKey(const Key('room-alice')));
      await tester.pumpAndSettle();
      expect(selectedRoomId.value, 'alice');
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.byKey(const Key('chat-panel')), findsOneWidget);
    });
  }
}
