import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void _expectSameRect(Rect expected, Rect actual, String label) {
  expect(
    actual,
    expected,
    reason:
        '$label moved during the open-DM interaction: expected $expected, got $actual',
  );
}

void main() {
  testWidgets('opening a DM has zero unintended layout jitter at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const Key('sidebar'));
    final chatPanel = find.byKey(const Key('chat-panel'));
    final composer = find.byKey(const Key('composer'));
    final messageList = find.byKey(const Key('message-list'));
    final kiteRow = find.byKey(const Key('room-kite'));
    final aliceRow = find.byKey(const Key('room-alice'));
    final bobRow = find.byKey(const Key('room-bob'));

    final initialSidebar = _rectOf(tester, sidebar);
    final initialChatPanel = _rectOf(tester, chatPanel);
    final initialComposer = _rectOf(tester, composer);
    final initialMessageList = _rectOf(tester, messageList);
    final initialKiteRow = _rectOf(tester, kiteRow);
    final initialAliceRow = _rectOf(tester, aliceRow);
    final initialBobRow = _rectOf(tester, bobRow);

    await tester.tap(find.byKey(const Key('room-alice')));

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      _expectSameRect(initialSidebar, _rectOf(tester, sidebar), 'sidebar');
      _expectSameRect(
        initialChatPanel,
        _rectOf(tester, chatPanel),
        'chat panel',
      );
      _expectSameRect(initialComposer, _rectOf(tester, composer), 'composer');
      _expectSameRect(
        initialMessageList,
        _rectOf(tester, messageList),
        'message list',
      );
      _expectSameRect(initialKiteRow, _rectOf(tester, kiteRow), 'Kite row');
      _expectSameRect(initialAliceRow, _rectOf(tester, aliceRow), 'Alice row');
      _expectSameRect(initialBobRow, _rectOf(tester, bobRow), 'Bob row');
      expect(tester.takeException(), isNull);
    }

    expect(selectedRoomId.value, 'alice');
    expect(find.text('Alice'), findsWidgets);
  });
}
