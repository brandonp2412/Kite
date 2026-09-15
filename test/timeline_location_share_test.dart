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

  testWidgets('composer shares a prepared static location', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final port = DeterministicTimelineLocationPort(latency: Duration.zero);
    timelineController.reset(locationPort: port);
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-option-location')), findsOneWidget);
    expect(
      find.byKey(const Key('attachment-option-live-location')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('attachment-option-location')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-share-sheet')), findsOneWidget);
    expect(find.text('Share location'), findsNWidgets(2));
    expect(find.text('Britomart'), findsOneWidget);

    await tester.tap(find.byKey(const Key('location-share-confirm')));
    await tester.pumpAndSettle();

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.mine, isTrue);
    expect(message.location?.kind, TimelineLocationKind.staticLocation);
    expect(message.location?.label, 'Britomart');
    expect(message.sendState.value, TimelineSendState.sent);
    expect(port.sentLocations, hasLength(1));
    expect(find.byKey(Key('message-location-${message.id}')), findsOneWidget);
  });

  testWidgets('live location stop is leaf-only and exposes progress state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final port = DeterministicTimelineLocationPort(
      latency: const Duration(milliseconds: 100),
    );
    timelineController.reset(locationPort: port);
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-live-location')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-share-confirm')));
    await tester.pumpAndSettle();

    final messages = timelineController.messagesFor('alice');
    final listIdentity = messages.value;
    final message = messages.value.last;
    final card = find.byKey(Key('message-location-${message.id}'));
    final before = tester.getRect(card);
    expect(message.location?.isLiveActive, isTrue);

    await tester.tap(find.byKey(Key('message-location-stop-${message.id}')));
    await tester.pump();
    expect(find.text('Ending live location'), findsOneWidget);
    expect(messages.value, same(listIdentity));
    expect(tester.getRect(card), before);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Live location ended'), findsOneWidget);
    expect(message.location?.isLiveActive, isFalse);
    expect(message.location?.isLiveStopping, isFalse);
    expect(messages.value, same(listIdentity));
    expect(tester.getRect(card), before);
    expect(port.stoppedEventIds, <String>[message.id]);
  });

  testWidgets('location permission denial retries without changing geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final port = DeterministicTimelineLocationPort(
      permission: TimelineLocationPermission.denied,
      latency: Duration.zero,
    );
    timelineController.reset(locationPort: port);
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-location')));
    await tester.pumpAndSettle();

    final slot = find.byKey(const Key('location-share-state-slot'));
    final deniedRect = tester.getRect(slot);
    expect(find.text('Allow location access'), findsOneWidget);
    expect(find.byKey(const Key('location-share-retry')), findsOneWidget);

    port.permission = TimelineLocationPermission.granted;
    await tester.tap(find.byKey(const Key('location-share-retry')));
    await tester.pumpAndSettle();
    expect(tester.getRect(slot), deniedRect);
    expect(find.text('Britomart'), findsOneWidget);
    expect(port.prepareRequests, 2);
  });

  testWidgets('permanent location denial exposes the system settings path', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final port = DeterministicTimelineLocationPort(
      permission: TimelineLocationPermission.permanentlyDenied,
      latency: Duration.zero,
    );
    timelineController.reset(locationPort: port);
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-live-location')));
    await tester.pumpAndSettle();

    expect(find.text('Location access is blocked'), findsOneWidget);
    await tester.tap(find.byKey(const Key('location-share-open-settings')));
    await tester.pump();
    expect(port.settingsRequests, 1);
  });
}
