import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  test('read receipts are normalized and remain leaf message state', () {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    final messages = timelineController.messagesFor('alice').value;
    final target = messages.last;
    final state = target.readByState;

    timelineController.updateReadReceipts('alice', target.id, <String>[
      ' Sam ',
      'Alice',
      'Sam',
      'You',
      '',
    ]);

    expect(target.readByState, same(state));
    expect(target.readBy, <String>['Alice', 'Sam']);
    expect(timelineController.messagesFor('alice').value, same(messages));
  });

  test('read receipts ignore incoming and unknown events', () {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    final messages = timelineController.messagesFor('alice').value;
    final incoming = messages[messages.length - 2];

    timelineController.updateReadReceipts('alice', incoming.id, const <String>[
      'Alice',
    ]);
    timelineController.updateReadReceipts(
      'alice',
      'missing-event',
      const <String>['Alice'],
    );

    expect(incoming.readBy, isEmpty);
  });

  testWidgets(
    'read receipt update preserves message geometry at 120 Hz and opens details',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      timelineController.reset(sendPort: DeterministicTimelineSendPort());
      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final target = timelineController.messagesFor('alice').value.last;
      final targetRow = find.byKey(const Key('message-row-alice-99'));
      final adjacentRow = find.byKey(const Key('message-row-alice-98'));
      final delivery = find.byKey(const Key('send-state-alice-99'));
      final targetRect = _rectOf(tester, targetRow);
      final adjacentRect = _rectOf(tester, adjacentRow);
      final deliveryRect = _rectOf(tester, delivery);

      timelineController.updateReadReceipts('alice', target.id, const <String>[
        'Alice',
        'Sam',
        'Maya',
        'Jordan',
      ]);

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, targetRow), targetRect);
        expect(_rectOf(tester, adjacentRow), adjacentRect);
        expect(_rectOf(tester, delivery), deliveryRect);
        expect(tester.takeException(), isNull);
      }

      final receipts = find.byKey(const Key('read-receipts-alice-99'));
      expect(receipts, findsOneWidget);
      expect(find.text('+1'), findsOneWidget);

      await tester.tap(receipts);
      await tester.pumpAndSettle();

      final details = find.byKey(const Key('read-receipt-details'));
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('Alice')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Jordan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Maya')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Sam')),
        findsOneWidget,
      );
    },
  );
}
