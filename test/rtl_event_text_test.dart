import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  setUp(() {
    selectRoom('alice');
    timelineController.reset();
  });

  testWidgets('message text follows its first strong bidi character', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final rtlMessage = timelineController.sendText('alice', 'مرحبا بك في Kite');
    final ltrMessage = timelineController.sendText('alice', 'Hello from Kite');

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pump();

    final rtlText = tester.widget<Text>(
      find.byKey(Key('message-body-${rtlMessage.id}')),
    );
    final ltrText = tester.widget<Text>(
      find.byKey(Key('message-body-${ltrMessage.id}')),
    );
    expect(rtlText.textDirection, TextDirection.rtl);
    expect(ltrText.textDirection, TextDirection.ltr);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('room-list geometry mirrors under RTL directionality', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('room-alice'));
    final avatar = find.descendant(
      of: row,
      matching: find.byType(CircleAvatar),
    );
    final title = find.descendant(of: row, matching: find.text('Alice'));
    expect(
      tester.getCenter(avatar).dx,
      greaterThan(tester.getCenter(title).dx),
    );
    expect(tester.takeException(), isNull);
  });
}
