import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Widget _appWithClockPreference(bool alwaysUse24HourFormat) {
  return KiteApp(
    themeMode: ThemeMode.light,
    locale: const Locale('en', 'US'),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: alwaysUse24HourFormat),
        child: const HomeScreen(),
      ),
    ),
  );
}

void main() {
  setUp(() {
    selectRoom('alice');
    timelineController.reset();
  });

  testWidgets('timeline renders one separator at each local day boundary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.messagesFor('alice').value = <TimelineMessage>[
      TimelineMessage(
        id: 'previous-day',
        sender: 'Alice',
        body: 'Late yesterday',
        mine: false,
        timeLabel: '23:58',
        sentAt: DateTime(2026, 9, 17, 23, 58),
      ),
      TimelineMessage(
        id: 'new-day',
        sender: 'Alice',
        body: 'Just after midnight',
        mine: false,
        timeLabel: '00:02',
        sentAt: DateTime(2026, 9, 18, 0, 2),
      ),
      TimelineMessage(
        id: 'same-day',
        sender: 'Alice',
        body: 'Later that morning',
        mine: false,
        timeLabel: '09:15',
        sentAt: DateTime(2026, 9, 18, 9, 15),
      ),
    ];

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pump();

    expect(
      find.byKey(const Key('date-separator-previous-day')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('date-separator-new-day')), findsOneWidget);
    expect(find.byKey(const Key('date-separator-same-day')), findsNothing);
    expect(find.text('Just after midnight'), findsOneWidget);
    expect(find.text('Later that morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synced timestamps follow locale and 12-hour preference', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.messagesFor('alice').value = <TimelineMessage>[
      TimelineMessage(
        id: 'localized-time',
        sender: 'Alice',
        body: 'Evening message',
        mine: false,
        timeLabel: '21:05',
        sentAt: DateTime(2026, 9, 18, 21, 5),
      ),
    ];

    await tester.pumpWidget(_appWithClockPreference(false));
    await tester.pump();

    final timestamp = tester.widget<Text>(
      find.byKey(const Key('message-time-localized-time')),
    );
    expect(timestamp.data, '9:05 PM');
  });

  testWidgets('optimistic local messages keep their explicit now label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.messagesFor('alice').value = <TimelineMessage>[
      TimelineMessage(
        id: 'kite-local-0',
        sender: 'You',
        body: 'Sending now',
        mine: true,
        timeLabel: 'now',
        sentAt: DateTime(2026, 9, 18, 21, 5),
        sendState: TimelineSendState.sending,
      ),
    ];

    await tester.pumpWidget(_appWithClockPreference(false));
    await tester.pump();

    final timestamp = tester.widget<Text>(
      find.byKey(const Key('message-time-kite-local-0')),
    );
    expect(timestamp.data, 'now');
  });

  testWidgets('synced timestamps respect the platform 24-hour preference', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.messagesFor('alice').value = <TimelineMessage>[
      TimelineMessage(
        id: '24-hour-time',
        sender: 'Alice',
        body: 'Evening message',
        mine: false,
        timeLabel: '9:05 PM',
        sentAt: DateTime(2026, 9, 18, 21, 5),
      ),
    ];

    await tester.pumpWidget(_appWithClockPreference(true));
    await tester.pump();

    final timestamp = tester.widget<Text>(
      find.byKey(const Key('message-time-24-hour-time')),
    );
    expect(timestamp.data, '21:05');
  });

  testWidgets('messages without calendar timestamps keep existing geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    timelineController.messagesFor('alice').value = <TimelineMessage>[
      TimelineMessage(
        id: 'fixture-a',
        sender: 'Alice',
        body: 'Fixture one',
        mine: false,
        timeLabel: '09:00',
      ),
      TimelineMessage(
        id: 'fixture-b',
        sender: 'Alice',
        body: 'Fixture two',
        mine: false,
        timeLabel: '09:07',
      ),
    ];

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pump();

    expect(find.byKey(const Key('date-separator-fixture-a')), findsNothing);
    expect(find.byKey(const Key('date-separator-fixture-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
