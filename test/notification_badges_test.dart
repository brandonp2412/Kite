import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_badges.dart';
import 'package:kite/features/notifications/notification_routing.dart';

final class _FakeRepository implements NotificationRepository {
  _FakeRepository(this.items);

  final List<KiteNotification> items;

  @override
  Iterable<KiteNotification> activeForAccount(String accountId) =>
      items.where((item) => item.destination.accountId == accountId);

  @override
  KiteNotification? notification(String routingId) {
    for (final item in items) {
      if (item.routingId == routingId) return item;
    }
    return null;
  }

  @override
  void remove(String routingId) {
    items.removeWhere((item) => item.routingId == routingId);
  }
}

final class _FakeBadgePort implements NotificationBadgePort {
  final counts = <int>[];
  Completer<void>? firstSetBlock;
  int calls = 0;

  @override
  Future<void> setBadgeCount(int count) async {
    calls += 1;
    if (calls == 1) await firstSetBlock?.future;
    counts.add(count);
  }
}

KiteNotification _notification({
  required String id,
  required String accountId,
  required KiteNotificationKind kind,
}) {
  return KiteNotification(
    id: id,
    kind: kind,
    destination: AppDestination.event(
      accountId: accountId,
      roomId: '!room:example.org',
      eventId: '\$$id',
    ),
  );
}

void main() {
  test(
    'badge count is account-aware and deduplicates notification ids',
    () async {
      final duplicate = _notification(
        id: 'same-id',
        accountId: 'work',
        kind: KiteNotificationKind.message,
      );
      final repository = _FakeRepository(<KiteNotification>[
        duplicate,
        duplicate,
        _notification(
          id: 'mention',
          accountId: 'work',
          kind: KiteNotificationKind.mention,
        ),
        _notification(
          id: 'personal',
          accountId: 'personal',
          kind: KiteNotificationKind.thread,
        ),
      ]);
      final badges = _FakeBadgePort();
      final coordinator = NotificationBadgeCoordinator(
        notifications: repository,
        badges: badges,
      );

      expect(await coordinator.refreshForAccounts(const <String>['work']), 2);
      expect(badges.counts, <int>[2]);

      expect(
        await coordinator.refreshForAccounts(const <String>[
          'work',
          'personal',
        ]),
        3,
      );
      expect(badges.counts.last, 3);
    },
  );

  test('same source id in two accounts counts as two notifications', () async {
    final repository = _FakeRepository(<KiteNotification>[
      _notification(
        id: 'same-id',
        accountId: 'work',
        kind: KiteNotificationKind.message,
      ),
      _notification(
        id: 'same-id',
        accountId: 'personal',
        kind: KiteNotificationKind.message,
      ),
    ]);
    final badges = _FakeBadgePort();
    final coordinator = NotificationBadgeCoordinator(
      notifications: repository,
      badges: badges,
    );

    expect(
      await coordinator.refreshForAccounts(const <String>['work', 'personal']),
      2,
    );
    expect(badges.counts, <int>[2]);
  });

  test('overlapping badge refreshes serialize and latest refresh sees current state', () async {
    final repository = _FakeRepository(<KiteNotification>[
      _notification(
        id: 'message',
        accountId: 'work',
        kind: KiteNotificationKind.message,
      ),
      _notification(
        id: 'call',
        accountId: 'work',
        kind: KiteNotificationKind.call,
      ),
    ]);
    final firstSetBlock = Completer<void>();
    final badges = _FakeBadgePort()..firstSetBlock = firstSetBlock;
    final coordinator = NotificationBadgeCoordinator(
      notifications: repository,
      badges: badges,
    );

    final first = coordinator.refreshForAccounts(const <String>['work']);
    await Future<void>.delayed(Duration.zero);
    repository.remove(KiteNotification.routingIdFor('work', 'message'));
    final second = coordinator.refreshForAccounts(const <String>['work']);
    await Future<void>.delayed(Duration.zero);

    expect(badges.calls, 1);
    expect(badges.counts, isEmpty);

    firstSetBlock.complete();
    expect(await first, 2);
    expect(await second, 1);
    expect(badges.counts, <int>[2, 1]);
  });

  test(
    'badge refresh reflects notification removal after read reconciliation',
    () async {
      final repository = _FakeRepository(<KiteNotification>[
        _notification(
          id: 'message',
          accountId: 'work',
          kind: KiteNotificationKind.message,
        ),
        _notification(
          id: 'call',
          accountId: 'work',
          kind: KiteNotificationKind.call,
        ),
      ]);
      final badges = _FakeBadgePort();
      final coordinator = NotificationBadgeCoordinator(
        notifications: repository,
        badges: badges,
      );

      expect(await coordinator.refreshForAccounts(const <String>['work']), 2);
      repository.remove(KiteNotification.routingIdFor('work', 'message'));
      expect(await coordinator.refreshForAccounts(const <String>['work']), 1);
      expect(badges.counts, <int>[2, 1]);
    },
  );

  test(
    'clear resets the platform badge without mutating notification state',
    () async {
      final repository = _FakeRepository(<KiteNotification>[
        _notification(
          id: 'message',
          accountId: 'work',
          kind: KiteNotificationKind.message,
        ),
      ]);
      final badges = _FakeBadgePort();
      final coordinator = NotificationBadgeCoordinator(
        notifications: repository,
        badges: badges,
      );

      expect(await coordinator.clear(), 0);
      expect(badges.counts, <int>[0]);
      expect(
        repository.notification(
          KiteNotification.routingIdFor('work', 'message'),
        ),
        isNotNull,
      );
    },
  );
}
