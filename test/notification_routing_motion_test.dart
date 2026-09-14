import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

final class _MotionNavigationPort implements AppNavigationPort {
  _MotionNavigationPort(this.revision);

  final ValueNotifier<int> revision;

  @override
  Future<void> open(AppDestination destination) async {
    revision.value += 1;
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets(
    'notification tap and read clearing preserve shell geometry at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      final notifications = FakeNotificationRepository(<KiteNotification>[
        const KiteNotification(
          id: 'event',
          kind: KiteNotificationKind.mention,
          destination: AppDestination.event(
            accountId: 'work',
            roomId: '!team:example.org',
            eventId: r'$event',
          ),
        ),
      ]);
      final cancellations = FakeNotificationCancellationPort();
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        cancellations: cancellations,
        accounts: FakeAccountActivationPort('personal'),
        navigation: _MotionNavigationPort(revision),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(
                  key: Key('notification-motion-header'),
                  width: double.infinity,
                  height: 72,
                  child: Center(child: Text('Notifications')),
                ),
                Expanded(
                  key: const Key('notification-motion-content'),
                  child: Center(
                    child: SizedBox(
                      key: const Key('notification-motion-status'),
                      width: 320,
                      height: 80,
                      child: ValueListenableBuilder<int>(
                        valueListenable: revision,
                        builder: (context, value, child) =>
                            Center(child: Text('notification-revision-$value')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final header = find.byKey(const Key('notification-motion-header'));
      final content = find.byKey(const Key('notification-motion-content'));
      final status = find.byKey(const Key('notification-motion-status'));
      final headerRect = _rectOf(tester, header);
      final contentRect = _rectOf(tester, content);
      final statusRect = _rectOf(tester, status);

      expect(await coordinator.tap('event'), isTrue);
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(_rectOf(tester, content), contentRect);
        expect(_rectOf(tester, status), statusRect);
        expect(tester.takeException(), isNull);
      }

      expect(
        await coordinator.markRoomRead(
          accountId: 'work',
          roomId: '!team:example.org',
        ),
        1,
      );
      revision.value += 1;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, header), headerRect);
        expect(_rectOf(tester, content), contentRect);
        expect(_rectOf(tester, status), statusRect);
        expect(tester.takeException(), isNull);
      }

      expect(notifications.notification('event'), isNull);
      expect(cancellations.cancelledIds, <String>['event']);
    },
  );
}
