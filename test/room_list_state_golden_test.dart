import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_filter.dart';

void main() {
  Future<void> pumpRoomList(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    selectRoom('kite');
    selectRoomListFilter(RoomListFilter.all);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('room-list message state baseline - light', (tester) async {
    await pumpRoomList(tester, themeMode: ThemeMode.light);

    await expectLater(
      find.byKey(const Key('sidebar')),
      matchesGoldenFile('goldens/room_list_states_light.png'),
    );
  });

  testWidgets('room-list message state baseline - dark', (tester) async {
    await pumpRoomList(tester, themeMode: ThemeMode.dark);

    await expectLater(
      find.byKey(const Key('sidebar')),
      matchesGoldenFile('goldens/room_list_states_dark.png'),
    );
  });
}
