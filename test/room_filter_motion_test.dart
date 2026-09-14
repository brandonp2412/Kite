import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/room_list_filter.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets(
    'room filter change has zero unintended geometry jitter at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      selectRoom('kite');
      selectRoomListFilter(RoomListFilter.all);
      await tester.pumpWidget(const KiteApp());
      await tester.pumpAndSettle();

      final sidebar = find.byKey(const Key('sidebar'));
      final header = find.byKey(const Key('home-header'));
      final filterBar = find.byKey(const Key('room-filter-bar'));
      final roomList = find.byKey(const Key('room-list'));
      final initialSidebar = _rectOf(tester, sidebar);
      final initialHeader = _rectOf(tester, header);
      final initialFilterBar = _rectOf(tester, filterBar);
      final initialRoomList = _rectOf(tester, roomList);

      await tester.tap(find.byKey(const Key('filter-unreads')));

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, sidebar), initialSidebar);
        expect(_rectOf(tester, header), initialHeader);
        expect(_rectOf(tester, filterBar), initialFilterBar);
        expect(_rectOf(tester, roomList), initialRoomList);
        expect(tester.takeException(), isNull);
      }

      expect(activeRoomListFilter.value, RoomListFilter.unreads);
      expect(find.byKey(const Key('room-alice')), findsNothing);
    },
  );
}
