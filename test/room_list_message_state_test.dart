import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/room_list_filter.dart';

void main() {
  testWidgets(
    'room rows render deterministic latest-event and notification state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      selectRoom('kite');
      selectRoomListFilter(RoomListFilter.all);
      await tester.pumpWidget(const KiteApp());
      await tester.pumpAndSettle();

      final kitePreview = tester.widget<Text>(
        find.byKey(const Key('preview-kite')),
      );
      expect(
        kitePreview.textSpan?.toPlainText(),
        'Kite Bot: Pinned benchmark fixture is ready',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mention-kite')),
          matching: find.text('@'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('unread-kite')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('favourite-kite')), findsOneWidget);

      final alicePreview = tester.widget<Text>(
        find.byKey(const Key('preview-alice')),
      );
      expect(alicePreview.textSpan?.toPlainText(), 'You: See you at 6?');
      expect(find.byKey(const Key('unread-alice')), findsNothing);
      expect(find.byKey(const Key('mention-alice')), findsNothing);
      expect(find.byKey(const Key('active-call-alice')), findsOneWidget);
      expect(find.byKey(const Key('favourite-alice')), findsOneWidget);

      final bobPreview = tester.widget<Text>(
        find.byKey(const Key('preview-bob')),
      );
      expect(
        bobPreview.textSpan?.toPlainText(),
        'Bob: Can you review the screenshots?',
      );
      expect(find.byKey(const Key('muted-bob')), findsOneWidget);
      expect(find.byKey(const Key('muted-activity-bob')), findsOneWidget);
      expect(find.byKey(const Key('active-call-bob')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('unread-bob')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
    },
  );
}
