import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_delivery.dart';
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
      final notifications = FakeNotificationRepository(<KiteNotification>[
        const KiteNotification(
          id: 'thread',
          kind: KiteNotificationKind.thread,
          destination: AppDestination.thread(
            accountId: 'work',
            roomId: '!team:example.org',
            eventId: r'$reply',
            threadRootEventId: r'$root',
          ),
        ),
        const KiteNotification(
          id: 'message',
          kind: KiteNotificationKind.message,
          destination: AppDestination.event(
            accountId: 'work',
            roomId: '!team:example.org',
            eventId: r'$message',
          ),
        ),
        const KiteNotification(
          id: 'remote-read',
          kind: KiteNotificationKind.mention,
          destination: AppDestination.event(
            accountId: 'work',
            roomId: '!other:example.org',
            eventId: r'$remoteRead',
          ),
        ),
      ]);
      final coordinator = NotificationCoordinator(
        notifications: notifications,
        accounts: accounts,
        navigation: navigation,
      );
      final notificationPrivacy = FakeNotificationPrivacyPort();
      final notificationDelivery = FakeNotificationDeliveryPort();
      final deliveryCoordinator = NotificationDeliveryCoordinator(
        privacy: notificationPrivacy,
        delivery: notificationDelivery,
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
          expect(await coordinator.tap('thread'), isTrue);
          await tester.pump();

          expect(
            coordinator.markRoomRead(
              accountId: 'work',
              roomId: '!team:example.org',
            ),
            2,
          );
          revision.value += 1;
          await tester.pump();

          expect(
            coordinator.reconcileReadEvents(
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
          expect(deliveryCoordinator.activePresentations, hasLength(48));
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
