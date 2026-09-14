import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/rooms/room_details_screen.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('opening room details preserves source geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('chat-header'));
    final initialHeader = _rectOf(tester, header);

    Future<List<Rect>> captureOpenMotion() async {
      final samples = <Rect>[];
      Size? destinationSize;
      await tester.tap(find.byKey(const Key('room-details-button')));
      await tester.pump();
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        final destination = find.byKey(const Key('room-details-screen'));
        expect(destination, findsOneWidget);
        final rect = _rectOf(tester, destination);
        destinationSize ??= rect.size;
        expect(rect.size, destinationSize);
        expect(tester.takeException(), isNull);
        samples.add(rect);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-details-screen')), findsOneWidget);
      return samples;
    }

    final firstRun = await captureOpenMotion();
    Navigator.of(tester.element(find.byKey(const Key('room-details-screen'))))
        .pop();
    await tester.pumpAndSettle();
    expect(_rectOf(tester, header), initialHeader);

    final secondRun = await captureOpenMotion();
    expect(secondRun, firstRun);
  });

  testWidgets('member search has zero unintended geometry jitter at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    await tester.pumpWidget(
      const MaterialApp(
        home: RoomDetailsScreen(roomId: 'kite', roomName: 'Kite'),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('member-search'));
    final list = find.byKey(const Key('member-list'));
    final initialSearch = _rectOf(tester, search);
    final initialList = _rectOf(tester, list);

    await tester.enterText(search, 'bob');

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, search), initialSearch);
      expect(_rectOf(tester, list), initialList);
      expect(tester.takeException(), isNull);
    }

    expect(find.byKey(const Key('member-@bob:example.org')), findsOneWidget);
  });

  testWidgets(
    'member profile and moderation preserve room geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      await tester.pumpWidget(
        const MaterialApp(
          home: RoomDetailsScreen(roomId: 'kite', roomName: 'Kite'),
        ),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('member-search'));
      final list = find.byKey(const Key('member-list'));
      final initialSearch = _rectOf(tester, search);
      final initialList = _rectOf(tester, list);

      await tester.tap(find.byKey(const Key('member-@bob:example.org')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, search), initialSearch);
        expect(_rectOf(tester, list), initialList);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('member-profile-sheet'));
      final settledSheet = _rectOf(tester, sheet);
      await tester.tap(find.byKey(const Key('member-promote')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, search), initialSearch);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, sheet), settledSheet);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const Key('member-kick')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, search), initialSearch);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('member-profile-sheet')), findsNothing);
      expect(_rectOf(tester, search), initialSearch);
    },
  );
}
