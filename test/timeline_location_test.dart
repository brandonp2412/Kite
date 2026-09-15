import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

TimelineMessage _locationMessage({
  required String id,
  required TimelineLocation location,
}) {
  return TimelineMessage(
    id: id,
    sender: 'Alice',
    body: '',
    mine: false,
    timeLabel: '10:14',
    location: location,
  );
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets('static and live locations render explicit non-colour state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final messages = timelineController.messagesFor('alice');
    messages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...messages.value,
      _locationMessage(
        id: 'static-location',
        location: const TimelineLocation(
          kind: TimelineLocationKind.staticLocation,
          latitude: -36.8485,
          longitude: 174.7633,
          label: 'Auckland CBD',
        ),
      ),
      _locationMessage(
        id: 'live-location',
        location: const TimelineLocation(
          kind: TimelineLocationKind.liveLocation,
          latitude: -36.8468,
          longitude: 174.7682,
          label: 'Britomart',
          isLiveActive: true,
        ),
      ),
    ]);
    selectRoom('alice');

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message-location-static-location')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('message-location-live-location')),
      findsOneWidget,
    );
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Live location'), findsOneWidget);
    expect(find.text('Auckland CBD'), findsOneWidget);
    expect(find.text('Britomart'), findsOneWidget);

    final semantics = tester.getSemantics(
      find.byKey(const Key('message-location-live-location')),
    );
    expect(semantics.label, contains('Live location: Britomart'));
    expect(semantics.label, contains('-36.8468, 174.7682'));
  });

  testWidgets('live location completion updates only the location leaf state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final live = _locationMessage(
      id: 'live-location',
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
    final listIdentity = messages.value;
    selectRoom('alice');

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    expect(find.text('Live location'), findsOneWidget);

    timelineController.updateLocation(
      'alice',
      live.id,
      live.location!.copyWith(isLiveActive: false),
    );
    await tester.pump();

    expect(messages.value, same(listIdentity));
    expect(find.text('Live location ended'), findsOneWidget);
    expect(
      find.byKey(const Key('message-location-live-location')),
      findsOneWidget,
    );
  });

  test('location updates reject a static/live kind mismatch', () {
    final message = _locationMessage(
      id: 'location',
      location: const TimelineLocation(
        kind: TimelineLocationKind.staticLocation,
        latitude: -36.8485,
        longitude: 174.7633,
        label: 'Auckland CBD',
      ),
    );
    final messages = timelineController.messagesFor('alice');
    messages.value = List<TimelineMessage>.unmodifiable(<TimelineMessage>[
      ...messages.value,
      message,
    ]);

    timelineController.updateLocation(
      'alice',
      message.id,
      const TimelineLocation(
        kind: TimelineLocationKind.liveLocation,
        latitude: -36.8485,
        longitude: 174.7633,
        label: 'Auckland CBD',
        isLiveActive: true,
      ),
    );

    expect(message.location?.kind, TimelineLocationKind.staticLocation);
    expect(message.location?.isLiveActive, isFalse);
  });
}
