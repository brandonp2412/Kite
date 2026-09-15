import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.width, closeTo(expected.width, 0.01));
  expect(actual.height, closeTo(expected.height, 0.01));
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets('live location state transition preserves geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final live = TimelineMessage(
      id: 'motion-live-location',
      sender: 'Alice',
      body: '',
      mine: false,
      timeLabel: '10:14',
      location: const TimelineLocation(
        kind: TimelineLocationKind.liveLocation,
        latitude: -36.8468,
        longitude: 174.7682,
        label: 'Britomart',
        isLiveActive: true,
      ),
    );
    final messages = timelineController.messagesFor('alice');
    messages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...messages.value,
      live,
    ]);
    selectRoom('alice');

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('message-location-motion-live-location'));
    final bubble = find.byKey(const Key('message-bubble-motion-live-location'));
    final cardRect = _rectOf(tester, card);
    final bubbleRect = _rectOf(tester, bubble);

    timelineController.updateLocation(
      'alice',
      live.id,
      live.location!.copyWith(isLiveActive: false),
    );

    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(microseconds: 8333));
      _expectRectClose(_rectOf(tester, card), cardRect);
      _expectRectClose(_rectOf(tester, bubble), bubbleRect);
    }

    expect(find.text('Live location ended'), findsOneWidget);
    _expectRectClose(_rectOf(tester, card), cardRect);
    _expectRectClose(_rectOf(tester, bubble), bubbleRect);
  });
}
