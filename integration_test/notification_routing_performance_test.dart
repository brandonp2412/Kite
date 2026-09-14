import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
import 'package:kite/features/notifications/notification_dispatch.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkNavigationPort implements AppNavigationPort {
  _BenchmarkNavigationPort(this.revision);

  final ValueNotifier<int> revision;
  AppDestination? lastDestination;

  @override
  Future<void> open(AppDestination destination) async {
    lastDestination = destination;
    revision.value += 1;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'notification routing and reconciliation have zero late Flutter frames',
    (tester) async {
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      final navigation = _BenchmarkNavigationPort(revision);
      final accounts = FakeAccountActivationPort('personal');
      final notifications = FakeNotificationRepository();
      final notificationPrivacy = FakeNotificationPrivacyPort();
      final notificationDelivery = FakeNotificationDeliveryPort();
      final deliveryCoordinator = NotificationDeliveryCoordinator(
        privacy: notificationPrivacy,
        delivery: notificationDelivery,
      );
      final dispatcher = NotificationDispatchCoordinator(
        notifications: notifications,
        delivery: deliveryCoordinator,
      );
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        cancellations: deliveryCoordinator,
        accounts: accounts,
        navigation: navigation,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, value, child) => Scaffold(
              body: Text(
                'notification-revision-$value',
                key: const Key('notification-routing-benchmark-status'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final result = await measureFrames(
        binding: binding,
        action: () async {
          for (final event in <MatrixNotificationEvent>[
            const MatrixNotificationEvent(
              id: 'thread',
              kind: MatrixNotificationEventKind.thread,
              accountId: 'work',
              roomId: '!team:example.org',
              eventId: r'$reply',
              threadRootEventId: r'$root',
              title: 'Thread reply',
              body: 'Deterministic thread notification',
            ),
            const MatrixNotificationEvent(
              id: 'message',
              kind: MatrixNotificationEventKind.message,
              accountId: 'work',
              roomId: '!team:example.org',
              eventId: r'$message',
              title: 'Message',
              body: 'Deterministic message notification',
            ),
            const MatrixNotificationEvent(
              id: 'remote-read',
              kind: MatrixNotificationEventKind.mention,
              accountId: 'work',
              roomId: '!other:example.org',
              eventId: r'$remoteRead',
              title: 'Mention',
              body: 'Deterministic mention notification',
            ),
            const MatrixNotificationEvent(
              id: 'invite',
              kind: MatrixNotificationEventKind.invite,
              accountId: 'work',
              roomId: '!invite:example.org',
              title: 'Invite',
              body: 'Deterministic invite notification',
            ),
          ]) {
            await dispatcher.dispatch(event);
          }
          expect(await coordinator.tap('thread'), isTrue);
          await tester.pump();

          expect(
            await coordinator.markRoomRead(
              accountId: 'work',
              roomId: '!team:example.org',
            ),
            2,
          );
          revision.value += 1;
          await tester.pump();

          expect(
            await coordinator.reconcileReadEvents(
              accountId: 'work',
              eventIds: const <String>[r'$remoteRead'],
            ),
            1,
          );
          for (var index = 0; index < 48; index += 1) {
            await deliveryCoordinator.upsert(
              notification: KiteNotification(
                id: 'summary-$index',
                kind: KiteNotificationKind.message,
                destination: AppDestination.event(
                  accountId: index.isEven ? 'work' : 'personal',
                  roomId: '!room${index % 4}:example.org',
                  eventId: '\$summary-$index',
                ),
              ),
              content: KiteNotificationContent(
                title: 'Sender $index',
                body: 'Deterministic notification body $index',
              ),
            );
          }
          notificationPrivacy.hideNotificationContents = true;
          await deliveryCoordinator.refreshPrivacy();
          expect(deliveryCoordinator.activePresentations, hasLength(49));
          expect(
            deliveryCoordinator.activePresentations.every(
              (presentation) => presentation.contentsHidden,
            ),
            isTrue,
          );
          expect(notificationDelivery.summaries, isNotEmpty);
          revision.value += 1;
          await tester.pump();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(accounts.activeAccountId, 'work');
      expect(navigation.lastDestination?.kind, AppDestinationKind.thread);
      expect(navigation.lastDestination?.eventId, r'$reply');
      expect(navigation.lastDestination?.threadRootEventId, r'$root');
      expect(notifications.notification('thread'), isNull);
      expect(notifications.notification('message'), isNull);
      expect(notifications.notification('remote-read'), isNull);
      expect(notifications.notification('invite'), isNotNull);
      expect(notificationDelivery.cancelledIds.take(3), <String>[
        'thread',
        'message',
        'remote-read',
      ]);

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['notification_routing_reconciliation'] =
          <String, dynamic>{
            'journey': 'notification_tap_and_read_reconciliation',
            'fixture': 'deterministic_notification_routing_v1',
            ...result,
            'result': 'PASS',
          };
    },
  );
}
