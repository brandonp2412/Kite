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
    reason: '$label moved during scrolling: expected $expected, got $actual',
  );
}

Future<void> _sampleFixedGeometry(
  WidgetTester tester,
  Map<String, (Finder, Rect)> fixtures,
) async {
  for (var index = 0; index < PerformanceContract.motionSamples; index++) {
    await tester.pump(PerformanceContract.motionFrame);
    for (final MapEntry(:key, :value) in fixtures.entries) {
      _expectSameRect(value.$2, _rectOf(tester, value.$1), key);
    }
    expect(tester.takeException(), isNull);
  }
}

void main() {
  setUp(() {
    selectRoom('kite');
  });

  testWidgets('room-list scroll keeps fixed chrome stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final fixtures = <String, (Finder, Rect)>{
      'sidebar': (
        find.byKey(const Key('sidebar')),
        _rectOf(tester, find.byKey(const Key('sidebar'))),
      ),
      'chat panel': (
        find.byKey(const Key('chat-panel')),
        _rectOf(tester, find.byKey(const Key('chat-panel'))),
      ),
      'composer': (
        find.byKey(const Key('composer')),
        _rectOf(tester, find.byKey(const Key('composer'))),
      ),
    };

    await tester.fling(
      find.byKey(const Key('room-list')),
      const Offset(0, -1100),
      5000,
    );
    await _sampleFixedGeometry(tester, fixtures);
  });

  testWidgets('timeline scroll keeps surrounding chrome stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final fixtures = <String, (Finder, Rect)>{
      'sidebar': (
        find.byKey(const Key('sidebar')),
        _rectOf(tester, find.byKey(const Key('sidebar'))),
      ),
      'chat header': (
        find.byKey(const Key('chat-header')),
        _rectOf(tester, find.byKey(const Key('chat-header'))),
      ),
      'message viewport': (
        find.byKey(const Key('message-list')),
        _rectOf(tester, find.byKey(const Key('message-list'))),
      ),
      'composer': (
        find.byKey(const Key('composer')),
        _rectOf(tester, find.byKey(const Key('composer'))),
      ),
    };

    await tester.fling(
      find.byKey(const Key('message-list')),
      const Offset(0, -1000),
      5000,
    );
    await _sampleFixedGeometry(tester, fixtures);
  });
}
