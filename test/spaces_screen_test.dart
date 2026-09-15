import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/home/spaces_screen.dart';

void main() {
  testWidgets('dedicated Spaces area browses joined and discoverable rooms', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = SpacesController();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spaces-screen')), findsOneWidget);
    expect(find.byKey(const Key('space-title-kite-space')), findsOneWidget);
    expect(
      find.byKey(const Key('space-room-row-kite-release')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('space-room-join-kite-release')),
      findsOneWidget,
    );
    expect(find.text('Joined'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('spaces-chip-people-space')));
    await tester.pump();
    expect(controller.selectedSpaceId.value, 'people-space');
    expect(find.byKey(const Key('space-title-people-space')), findsOneWidget);
    expect(find.byKey(const Key('space-room-row-coffee-club')), findsOneWidget);

    await tester.tap(find.byKey(const Key('space-room-join-coffee-club')));
    await tester.pump();
    expect(
      controller.joinStateFor('coffee-club').value,
      SpaceRoomJoinState.joining,
    );
    expect(find.byKey(const Key('space-room-joining')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(
      controller.joinStateFor('coffee-club').value,
      SpaceRoomJoinState.joined,
    );
    expect(find.byKey(const Key('space-room-join-coffee-club')), findsNothing);
  });

  test('controller rejects unknown Spaces and preserves joined room state', () {
    final controller = SpacesController();
    expect(() => controller.selectSpace('missing-space'), throwsArgumentError);
    expect(controller.joinStateFor('kite').value, SpaceRoomJoinState.joined);
    expect(() => controller.joinStateFor('missing-room'), throwsArgumentError);
  });
  testWidgets('desktop Spaces layout uses a stable navigation rail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = SpacesController();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: SpacesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spaces-rail')), findsOneWidget);
    expect(find.byKey(const Key('spaces-chip-row')), findsNothing);
    expect(find.byKey(const Key('space-body-kite-space')), findsOneWidget);

    final headerRect = tester.getRect(find.byKey(const Key('spaces-header')));
    await tester.tap(find.byKey(const Key('spaces-rail-people-space')));
    await tester.pump();

    expect(find.byKey(const Key('space-body-people-space')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('spaces-header'))), headerRect);
  });
}
