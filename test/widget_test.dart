import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';

void main() {
  testWidgets('Kite deterministic shell renders', (tester) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);
  });

  testWidgets('KiteApp keeps every route inside system safe areas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(
      left: 10,
      top: 24,
      right: 10,
      bottom: 32,
    );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      const KiteApp(
        home: Scaffold(body: SizedBox.expand(key: Key('safe-area-content'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('safe-area-content'))),
      const Rect.fromLTRB(10, 24, 380, 812),
    );
  });

  testWidgets('home search reduces the chat list without extra filter chrome', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('space-filter-row')), findsNothing);
    expect(find.byKey(const Key('room-filter-row')), findsNothing);

    await tester.enterText(find.byKey(const Key('home-search')), 'Alice');
    await tester.pump();

    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('room-kite')), findsNothing);
  });
}
