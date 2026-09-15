import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      locationPort: DeterministicTimelineLocationPort(),
    );
    selectRoom('kite');
  });

  testWidgets(
    'location sharing overlays preserve composer geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      timelineController.reset(
        locationPort: DeterministicTimelineLocationPort(latency: Duration.zero),
      );
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final composer = find.byKey(const Key('composer'));
      final initialComposer = tester.getRect(composer);
      const frame = Duration(microseconds: 8333);

      await tester.tap(find.byKey(const Key('composer-attach')));
      for (var index = 0; index < 30; index++) {
        await tester.pump(frame);
        expect(tester.getRect(composer), initialComposer);
      }
      expect(find.byKey(const Key('attachment-picker-sheet')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('attachment-option-live-location')),
      );
      for (var index = 0; index < 30; index++) {
        await tester.pump(frame);
        expect(tester.getRect(composer), initialComposer);
      }
      expect(find.byKey(const Key('location-share-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('location-share-confirm')));
      for (var index = 0; index < 30; index++) {
        await tester.pump(frame);
        expect(tester.getRect(composer), initialComposer);
      }
      expect(find.byKey(const Key('location-share-sheet')), findsNothing);

      final message = timelineController.messagesFor('alice').value.last;
      final card = find.byKey(Key('message-location-${message.id}'));
      final cardRect = tester.getRect(card);
      await tester.tap(find.byKey(Key('message-location-stop-${message.id}')));
      for (var index = 0; index < 16; index++) {
        await tester.pump(frame);
        expect(tester.getRect(card), cardRect);
      }
      expect(find.text('Live location ended'), findsOneWidget);
    },
  );
}
