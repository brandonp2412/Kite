import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/room_content_gallery.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:signals/signals.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('gallery tab transition preserves header geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final messages = signal<List<TimelineMessage>>(<TimelineMessage>[
      TimelineMessage(
        id: 'photo',
        sender: 'Maya',
        body: '',
        mine: false,
        timeLabel: '10:12',
        attachment: const TimelineAttachment(
          id: 'photo-attachment',
          kind: TimelineAttachmentKind.image,
          name: 'photo.jpg',
          sizeLabel: '2 MB · Photo',
        ),
      ),
      TimelineMessage(
        id: 'file',
        sender: 'Maya',
        body: '',
        mine: false,
        timeLabel: '10:14',
        attachment: const TimelineAttachment(
          id: 'file-attachment',
          kind: TimelineAttachmentKind.file,
          name: 'notes.pdf',
          sizeLabel: '500 KB · PDF',
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: RoomContentGallery(roomId: 'design', messages: messages),
      ),
    );
    await tester.pumpAndSettle();

    final gallery = find.byKey(const Key('room-content-gallery'));
    final header = find.byKey(const Key('room-content-gallery-header'));
    final tabs = find.byKey(const Key('room-content-tabs'));
    final initialGallery = _rectOf(tester, gallery);
    final initialHeader = _rectOf(tester, header);
    final initialTabs = _rectOf(tester, tabs);

    await tester.tap(find.byKey(const Key('room-content-tab-files')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, gallery), initialGallery);
      expect(_rectOf(tester, header), initialHeader);
      expect(_rectOf(tester, tabs), initialTabs);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-content-file-file')), findsOneWidget);
  });
}
