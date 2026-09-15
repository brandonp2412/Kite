import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/features/notifications/notification_ingress.dart';
import 'package:kite/features/notifications/notification_routing.dart';
import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_account_store_registry.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_restoration.dart';
import 'package:kite/matrix/matrix_runtime_bindings.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/matrix_session_routing_adapter.dart';
import 'package:kite/matrix/matrix_session_runtime.dart';
import 'package:kite/matrix/presentation_store.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';
import 'package:signals/signals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('process recreation restores account cache and navigation before sync resumes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-runtime-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final presentationStore = FileMatrixPresentationStore(
      Directory('${directory.path}/presentation'),
    );
    final restoration = MatrixRestorationCoordinator(
      FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
    );

    final firstBoundaries = <String, _FakeBoundary>{};
    final firstRegistry = _registry(firstBoundaries, presentationStore);
    final firstSession = MatrixSessionRuntime(
      accounts: firstRegistry,
      restoration: restoration,
      isAccountAvailable: (_) => true,
    );

    await firstSession.activateAccount('@alice:example.org');
    await firstSession.navigate(
      const MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$remember-me:example.org',
      ),
    );
    await firstRegistry.flushPresentationWrites();
    await firstRegistry.dispose();

    final secondBoundaries = <String, _FakeBoundary>{};
    final secondRegistry = _registry(secondBoundaries, presentationStore);
    addTearDown(secondRegistry.dispose);
    final secondSession = MatrixSessionRuntime(
      accounts: secondRegistry,
      restoration: MatrixRestorationCoordinator(
        FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
      ),
      isAccountAvailable: (accountId) => accountId == '@alice:example.org',
    );

    expect(await secondSession.restoreCachedState(), isTrue);
    expect(secondRegistry.activeAccountId.value, '@alice:example.org');
    expect(
      secondSession.navigationTarget.value,
      const MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$remember-me:example.org',
      ),
    );
    expect(
      secondRegistry.activeCache
          ?.roomSummarySignal('!alice:example.org')
          .value
          ?.displayName,
      'Alice room',
    );

    final restoredBoundary = secondBoundaries['@alice:example.org']!;
    expect(restoredBoundary.openCalls, 0);
    expect(restoredBoundary.startCalls, 0);

    await secondSession.resumeSync();

    expect(restoredBoundary.openCalls, 1);
    expect(restoredBoundary.startCalls, 1);
    expect(
      restoredBoundary.lastSyncConfiguration?.resumeFromCursor,
      'alice-start-1',
    );
    expect(secondRegistry.activeCache?.lastSyncCursor, 'alice-start-1');
  });

  test(
    'session facade forwards lifecycle and connectivity to active account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-lifecycle-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(
          FileMatrixRestorationStore(
            File('${directory.path}/restoration.json'),
          ),
        ),
        isAccountAvailable: (_) => true,
      );

      await session.activateAccount('@alice:example.org');
      final boundary = boundaries['@alice:example.org']!;
      expect(boundary.startCalls, 1);
      expect(session.syncState, isNotNull);

      final lifecycle = MatrixLifecycleBinding(session);
      await lifecycle.handleLifecycleState(AppLifecycleState.paused);
      expect(boundary.stopCalls, 1);
      await lifecycle.handleLifecycleState(AppLifecycleState.resumed);
      expect(boundary.startCalls, 2);

      final changes = StreamController<MatrixNetworkState>.broadcast(
        sync: true,
      );
      final connectivity = MatrixConnectivityBinding(
        session,
        MatrixNetworkState.online,
        changes.stream,
      );
      await connectivity.attach();
      changes.add(MatrixNetworkState.offline);
      while (boundary.stopCalls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      changes.add(MatrixNetworkState.online);
      while (boundary.startCalls < 3) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(boundary.stopCalls, 2);
      expect(boundary.startCalls, 3);
      await connectivity.detach();
      await changes.close();
    },
  );

  test('account switch exposes matching navigation before slow sync startup completes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-switch-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final bobStartGate = Completer<void>();
    final boundaries = <String, _FakeBoundary>{};
    final restorationStore = FileMatrixRestorationStore(
      File('${directory.path}/restoration.json'),
    );
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
      startGates: <String, Completer<void>>{'@bob:example.org': bobStartGate},
    );
    addTearDown(registry.dispose);
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(restorationStore),
      isAccountAvailable: (_) => true,
    );
    const aliceTarget = MatrixNavigationTarget.room('!alice:example.org');
    const bobTarget = MatrixNavigationTarget.event(
      '!bob:example.org',
      r'$bob-event:example.org',
    );

    await session.activateAccount('@alice:example.org', target: aliceTarget);
    final switching = session.activateAccount(
      '@bob:example.org',
      target: bobTarget,
    );
    while (registry.activeAccountId.value != '@bob:example.org') {
      await Future<void>.delayed(Duration.zero);
    }
    while ((boundaries['@bob:example.org']?.startCalls ?? 0) == 0) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(session.navigationTarget.value, bobTarget);
    final persistedDuringStart = await restorationStore.load();
    expect(persistedDuringStart?.accountId, '@bob:example.org');
    expect(persistedDuringStart?.navigationTarget, bobTarget);

    bobStartGate.complete();
    await switching;
    expect(registry.activeAccountId.value, '@bob:example.org');
    expect(session.navigationTarget.value, bobTarget);
  });

  test(
    'failed account switch restores prior navigation and restoration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-switch-failure-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final boundaries = <String, _FakeBoundary>{};
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
        failStartFor: <String>{'@broken:example.org'},
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );
      const aliceTarget = MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$alice-event:example.org',
      );
      const brokenTarget = MatrixNavigationTarget.room('!broken:example.org');

      await session.activateAccount('@alice:example.org', target: aliceTarget);
      await expectLater(
        session.activateAccount('@broken:example.org', target: brokenTarget),
        throwsA(isA<StateError>()),
      );

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(registry.loadedAccountIds, <String>['@alice:example.org']);
      expect(session.navigationTarget.value, aliceTarget);
      final restored = await restorationStore.load();
      expect(restored?.accountId, '@alice:example.org');
      expect(restored?.navigationTarget, aliceTarget);
    },
  );

  test('failed account switch rolls account and navigation back atomically', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-switch-atomic-rollback-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final boundaries = <String, _FakeBoundary>{};
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
      failStartFor: <String>{'@broken:example.org'},
    );
    addTearDown(registry.dispose);
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(
        FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
      ),
      isAccountAvailable: (_) => true,
    );
    const aliceTarget = MatrixNavigationTarget.room('!alice:example.org');
    const brokenTarget = MatrixNavigationTarget.room('!broken:example.org');

    await session.activateAccount('@alice:example.org', target: aliceTarget);
    final observedPairs = <String>[];
    final disposeEffect = effect(() {
      observedPairs.add(
        '${registry.activeAccountId.value}|${session.navigationTarget.value.roomIdOrAlias}',
      );
    });
    addTearDown(disposeEffect);

    await expectLater(
      session.activateAccount('@broken:example.org', target: brokenTarget),
      throwsA(isA<StateError>()),
    );

    expect(observedPairs, contains('@broken:example.org|!broken:example.org'));
    expect(
      observedPairs,
      isNot(contains('@alice:example.org|!broken:example.org')),
    );
    expect(
      observedPairs,
      isNot(contains('@broken:example.org|!alice:example.org')),
    );
    expect(observedPairs.last, '@alice:example.org|!alice:example.org');
  });

  test('failed account persistence rolls account and navigation back atomically', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-switch-persistence-rollback-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final registry = _registry(
      <String, _FakeBoundary>{},
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
    );
    addTearDown(registry.dispose);
    final restorationStore = _ControllableRestorationStore();
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(restorationStore),
      isAccountAvailable: (_) => true,
    );
    const aliceTarget = MatrixNavigationTarget.room('!alice:example.org');
    const bobTarget = MatrixNavigationTarget.room('!bob:example.org');

    await session.activateAccount('@alice:example.org', target: aliceTarget);
    final observedPairs = <String>[];
    final disposeEffect = effect(() {
      observedPairs.add(
        '${registry.activeAccountId.value}|${session.navigationTarget.value.roomIdOrAlias}',
      );
    });
    addTearDown(disposeEffect);
    restorationStore.failNextSave = true;

    await expectLater(
      session.activateAccount('@bob:example.org', target: bobTarget),
      throwsStateError,
    );

    expect(
      observedPairs,
      isNot(contains('@alice:example.org|!bob:example.org')),
    );
    expect(
      observedPairs,
      isNot(contains('@bob:example.org|!alice:example.org')),
    );
    expect(observedPairs.last, '@alice:example.org|!alice:example.org');
    expect(registry.loadedAccountIds, <String>['@alice:example.org']);
    expect(restorationStore.snapshot?.accountId, '@alice:example.org');
    expect(restorationStore.snapshot?.navigationTarget, aliceTarget);
  });

  test(
    'queued account switch failure rolls navigation back to preceding switch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-switch-order-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final boundaries = <String, _FakeBoundary>{};
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
        failStartFor: <String>{'@broken:example.org'},
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );
      const aliceTarget = MatrixNavigationTarget.room('!alice:example.org');
      const bobTarget = MatrixNavigationTarget.room('!bob:example.org');
      const brokenTarget = MatrixNavigationTarget.room('!broken:example.org');

      await session.activateAccount('@alice:example.org', target: aliceTarget);
      final bobSwitch = session.activateAccount(
        '@bob:example.org',
        target: bobTarget,
      );
      final brokenSwitch = session.activateAccount(
        '@broken:example.org',
        target: brokenTarget,
      );

      await bobSwitch;
      await expectLater(brokenSwitch, throwsA(isA<StateError>()));

      expect(registry.activeAccountId.value, '@bob:example.org');
      expect(session.navigationTarget.value, bobTarget);
      final restored = await restorationStore.load();
      expect(restored?.accountId, '@bob:example.org');
      expect(restored?.navigationTarget, bobTarget);
    },
  );

  test('unavailable account activation cannot allocate a runtime or replace active state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-unavailable-account-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final restorationStore = FileMatrixRestorationStore(
      File('${directory.path}/restoration.json'),
    );
    final boundaries = <String, _FakeBoundary>{};
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
    );
    addTearDown(registry.dispose);
    final availableAccounts = <String>{'@alice:example.org'};
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(restorationStore),
      isAccountAvailable: availableAccounts.contains,
    );
    const aliceTarget = MatrixNavigationTarget.room('!alice:example.org');

    await session.activateAccount('@alice:example.org', target: aliceTarget);
    await expectLater(
      session.activateAccount(
        '@removed:example.org',
        target: const MatrixNavigationTarget.room('!removed:example.org'),
      ),
      throwsA(isA<StateError>()),
    );

    expect(boundaries.keys, <String>{'@alice:example.org'});
    expect(registry.loadedAccountIds, <String>['@alice:example.org']);
    expect(registry.activeAccountId.value, '@alice:example.org');
    expect(session.navigationTarget.value, aliceTarget);
    final restored = await restorationStore.load();
    expect(restored?.accountId, '@alice:example.org');
    expect(restored?.navigationTarget, aliceTarget);
  });

  test('notification account checks do not allocate inactive runtimes and stale taps stay isolated', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-notification-account-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final boundaries = <String, _FakeBoundary>{};
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
    );
    addTearDown(registry.dispose);
    final availableAccounts = <String>{
      '@alice:example.org',
      '@bob:example.org',
    };
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(
        FileMatrixRestorationStore(File('${directory.path}/restoration.json')),
      ),
      isAccountAvailable: availableAccounts.contains,
    );
    await session.activateAccount('@alice:example.org');
    final routing = MatrixSessionRoutingAdapter(session);

    expect(await routing.containsAccount('@bob:example.org'), isTrue);
    expect(await routing.containsAccount(' @bob:example.org '), isFalse);
    expect(boundaries.containsKey('@bob:example.org'), isFalse);

    final acceptedIngress = <NotificationIngressResult>[];
    final ingress = NotificationIngressCoordinator(
      accounts: routing,
      onAccepted: (result) async => acceptedIngress.add(result),
    );
    final knownAccountIngress = await ingress.receive(
      transport: NotificationIngressTransport.fcm,
      data: <String, String?>{
        'notification_id': 'bob-message',
        'kind': 'message',
        'account_id': '@bob:example.org',
        'room_id': '!bob:example.org',
        'event_id': r'$bob-message',
      },
    );
    expect(knownAccountIngress.accepted, isTrue);
    expect(acceptedIngress, hasLength(1));
    expect(boundaries.containsKey('@bob:example.org'), isFalse);

    availableAccounts.remove('@bob:example.org');
    final removedAccountIngress = await ingress.receive(
      transport: NotificationIngressTransport.backgroundSync,
      data: <String, String?>{
        'notification_id': 'stale-bob-ingress',
        'kind': 'message',
        'account_id': '@bob:example.org',
        'room_id': '!bob:example.org',
        'event_id': r'$stale-bob-ingress',
      },
    );
    expect(removedAccountIngress.accepted, isFalse);
    expect(
      removedAccountIngress.failure,
      NotificationIngressFailure.unknownAccount,
    );
    expect(acceptedIngress, hasLength(1));

    final coordinator = NotificationCoordinator(
      notifications: FakeNotificationRepository(<KiteNotification>[
        const KiteNotification(
          id: 'stale-bob',
          kind: KiteNotificationKind.message,
          destination: AppDestination.room(
            accountId: '@bob:example.org',
            roomId: '!bob:example.org',
          ),
        ),
      ]),
      cancellations: FakeNotificationCancellationPort(),
      accounts: routing,
      navigation: routing,
    );

    expect(
      await coordinator.tap(
        KiteNotification.routingIdFor(
          accountId: '@bob:example.org',
          notificationId: 'stale-bob',
        ),
      ),
      isFalse,
    );
    expect(registry.activeAccountId.value, '@alice:example.org');
    expect(boundaries.containsKey('@bob:example.org'), isFalse);
    expect(registry.loadedAccountIds, <String>['@alice:example.org']);
  });

  test(
    'removing the active account clears navigation and process restoration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-remove-active-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );
      const target = MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$alice-event:example.org',
      );

      await session.activateAccount('@alice:example.org', target: target);
      expect(await restorationStore.load(), isNotNull);

      expect(await session.removeAccount('@alice:example.org'), isTrue);

      expect(registry.activeAccountId.value, isNull);
      expect(registry.cacheFor('@alice:example.org'), isNull);
      expect(
        session.navigationTarget.value,
        const MatrixNavigationTarget.home(),
      );
      expect(await restorationStore.load(), isNull);
    },
  );

  test(
    'removing an inactive account preserves active navigation and restoration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-remove-inactive-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );
      const bobTarget = MatrixNavigationTarget.room('!bob:example.org');
      const aliceTarget = MatrixNavigationTarget.event(
        '!alice:example.org',
        r'$alice-event:example.org',
      );

      await session.activateAccount('@bob:example.org', target: bobTarget);
      await session.activateAccount('@alice:example.org', target: aliceTarget);

      expect(await session.removeAccount('@bob:example.org'), isTrue);

      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(registry.cacheFor('@bob:example.org'), isNull);
      expect(session.navigationTarget.value, aliceTarget);
      final restored = await restorationStore.load();
      expect(restored?.accountId, '@alice:example.org');
      expect(restored?.navigationTarget, aliceTarget);
    },
  );

  test(
    'rejects unsafe navigation before visible or persisted state changes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-navigation-validation-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final registry = _registry(
        <String, _FakeBoundary>{},
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );
      const initialTarget = MatrixNavigationTarget.room('!initial:example.org');

      await session.activateAccount(
        '@alice:example.org',
        target: initialTarget,
      );
      await expectLater(
        session.navigate(
          const MatrixNavigationTarget.event('!room:example.org', ''),
        ),
        throwsArgumentError,
      );

      expect(session.navigationTarget.value, initialTarget);
      expect((await restorationStore.load())?.navigationTarget, initialTarget);
    },
  );

  test('navigation persistence failure rolls back the visible target and can retry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-navigation-rollback-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final boundaries = <String, _FakeBoundary>{};
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
    );
    addTearDown(registry.dispose);
    final restorationStore = _ControllableRestorationStore();
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(restorationStore),
      isAccountAvailable: (_) => true,
    );
    const initialTarget = MatrixNavigationTarget.room('!initial:example.org');
    const failedTarget = MatrixNavigationTarget.room('!failed:example.org');
    const recoveredTarget = MatrixNavigationTarget.room(
      '!recovered:example.org',
    );

    await session.activateAccount('@alice:example.org', target: initialTarget);
    restorationStore.failNextSave = true;

    await expectLater(session.navigate(failedTarget), throwsStateError);

    expect(session.navigationTarget.value, initialTarget);
    expect(restorationStore.snapshot?.navigationTarget, initialTarget);

    await session.navigate(recoveredTarget);
    expect(session.navigationTarget.value, recoveredTarget);
    expect(restorationStore.snapshot?.navigationTarget, recoveredTarget);
  });

  test(
    'queued navigation after active account removal cannot persist stale state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-remove-queue-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => true,
      );

      await session.activateAccount('@alice:example.org');
      final removal = session.removeAccount('@alice:example.org');
      final navigation = session.navigate(
        const MatrixNavigationTarget.room('!stale:example.org'),
      );

      expect(await removal, isTrue);
      await expectLater(navigation, throwsStateError);
      expect(
        session.navigationTarget.value,
        const MatrixNavigationTarget.home(),
      );
      expect(await restorationStore.load(), isNull);
    },
  );

  test('notification routing switches account and preserves thread and call identity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kite-session-notification-routing-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final restorationStore = FileMatrixRestorationStore(
      File('${directory.path}/restoration.json'),
    );
    final boundaries = <String, _FakeBoundary>{};
    final registry = _registry(
      boundaries,
      FileMatrixPresentationStore(Directory('${directory.path}/presentation')),
    );
    addTearDown(registry.dispose);
    final session = MatrixSessionRuntime(
      accounts: registry,
      restoration: MatrixRestorationCoordinator(restorationStore),
      isAccountAvailable: (_) => true,
    );
    await session.activateAccount('@alice:example.org');

    final routing = MatrixSessionRoutingAdapter(session);
    final notifications = FakeNotificationRepository(<KiteNotification>[
      const KiteNotification(
        id: 'thread-notification',
        kind: KiteNotificationKind.thread,
        destination: AppDestination.thread(
          accountId: '@bob:example.org',
          roomId: '!team:example.org',
          eventId: r'$reply',
          threadRootEventId: r'$root',
        ),
      ),
      const KiteNotification(
        id: 'call-notification',
        kind: KiteNotificationKind.call,
        destination: AppDestination.call(
          accountId: '@bob:example.org',
          roomId: '!calls:example.org',
          callId: 'call-7',
        ),
      ),
    ]);
    final coordinator = NotificationCoordinator(
      notifications: notifications,
      cancellations: FakeNotificationCancellationPort(),
      accounts: routing,
      navigation: routing,
    );

    expect(
      await coordinator.tap(
        KiteNotification.routingIdFor(
          accountId: '@bob:example.org',
          notificationId: 'thread-notification',
        ),
      ),
      isTrue,
    );
    expect(registry.activeAccountId.value, '@bob:example.org');
    expect(
      session.navigationTarget.value,
      const MatrixNavigationTarget.thread(
        '!team:example.org',
        r'$reply',
        r'$root',
      ),
    );
    expect(
      (await restorationStore.load())?.navigationTarget,
      session.navigationTarget.value,
    );

    expect(
      await coordinator.tap(
        KiteNotification.routingIdFor(
          accountId: '@bob:example.org',
          notificationId: 'call-notification',
        ),
      ),
      isTrue,
    );
    expect(
      session.navigationTarget.value,
      const MatrixNavigationTarget.call('!calls:example.org', callId: 'call-7'),
    );
    expect(
      (await restorationStore.load())?.navigationTarget,
      session.navigationTarget.value,
    );
  });

  test(
    'session routing refuses cross-account navigation before activation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-routing-guard-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final registry = _registry(
        <String, _FakeBoundary>{},
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(
          FileMatrixRestorationStore(
            File('${directory.path}/restoration.json'),
          ),
        ),
        isAccountAvailable: (_) => true,
      );
      await session.activateAccount('@alice:example.org');
      final routing = MatrixSessionRoutingAdapter(session);

      await expectLater(
        routing.open(
          const AppDestination.room(
            accountId: '@bob:example.org',
            roomId: '!team:example.org',
          ),
        ),
        throwsStateError,
      );
      expect(registry.activeAccountId.value, '@alice:example.org');
      expect(
        session.navigationTarget.value,
        const MatrixNavigationTarget.home(),
      );
    },
  );

  test(
    'stale process restoration is cleared without opening an SDK store',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-session-stale-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final restorationStore = FileMatrixRestorationStore(
        File('${directory.path}/restoration.json'),
      );
      await restorationStore.save(
        const MatrixRestorationSnapshot(
          accountId: '@removed:example.org',
          navigationTarget: MatrixNavigationTarget.room('!old:example.org'),
        ),
      );

      final boundaries = <String, _FakeBoundary>{};
      final registry = _registry(
        boundaries,
        FileMatrixPresentationStore(
          Directory('${directory.path}/presentation'),
        ),
      );
      addTearDown(registry.dispose);
      final session = MatrixSessionRuntime(
        accounts: registry,
        restoration: MatrixRestorationCoordinator(restorationStore),
        isAccountAvailable: (_) => false,
      );

      expect(await session.restoreCachedState(), isFalse);
      expect(registry.activeAccountId.value, isNull);
      expect(
        session.navigationTarget.value,
        const MatrixNavigationTarget.home(),
      );
      expect(boundaries, isEmpty);
      expect(await restorationStore.load(), isNull);
    },
  );
}

MatrixAccountRuntimeRegistry _registry(
  Map<String, _FakeBoundary> boundaries,
  MatrixPresentationStore presentationStore, {
  Map<String, Completer<void>> startGates = const <String, Completer<void>>{},
  Set<String> failStartFor = const <String>{},
}) {
  return MatrixAccountRuntimeRegistry(
    storeRegistry: MatrixAccountStoreRegistry(
      rootPath: '/data/kite/matrix',
      encryptionKeyIdForAccount: (accountId) => 'matrix-key:$accountId',
    ),
    boundaryFactory: (accountId) => boundaries.putIfAbsent(
      accountId,
      () => _FakeBoundary(
        accountId,
        startGate: startGates[accountId],
        failStart: failStartFor.contains(accountId),
      ),
    ),
    initialActivity: MatrixAppActivity.foreground,
    initialNetworkState: MatrixNetworkState.online,
    presentationStore: presentationStore,
  );
}

final class _ControllableRestorationStore implements MatrixRestorationStore {
  MatrixRestorationSnapshot? snapshot;
  bool failNextSave = false;

  @override
  Future<MatrixRestorationSnapshot?> load() async => snapshot;

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('deterministic restoration save failure');
    }
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}

final class _FakeBoundary implements MatrixSdkBoundary {
  _FakeBoundary(this.accountId, {this.startGate, this.failStart = false});

  final String accountId;
  final Completer<void>? startGate;
  final bool failStart;
  final StreamController<MatrixSyncBatch> _sync =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  int openCalls = 0;
  int startCalls = 0;
  MatrixSdkSyncConfiguration? lastSyncConfiguration;
  int stopCalls = 0;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.incrementalSync,
    MatrixSdkCapability.backPagination,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches => _sync.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) async {
    openCalls += 1;
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) async {
    startCalls += 1;
    lastSyncConfiguration = configuration;
    if (failStart) throw StateError('deterministic start failure');
    await startGate?.future;
    final localpart = accountId.substring(1, accountId.indexOf(':'));
    _sync.add(
      MatrixSyncBatch(
        cursor: '$localpart-start-$startCalls',
        rooms: <MatrixRoomDelta>[
          MatrixRoomDelta(
            roomId: '!$localpart:example.org',
            summary: MatrixRoomSummary(
              roomId: '!$localpart:example.org',
              displayName:
                  '${localpart[0].toUpperCase()}${localpart.substring(1)} room',
              lastActivity: DateTime.utc(2026, 9, 15, 5),
              streamPosition: startCalls,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> stopSync() async {
    stopCalls += 1;
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) async {
    return MatrixPaginationPage(
      roomId: roomId,
      events: const <MatrixTimelineEvent>[],
      reachedStart: true,
    );
  }

  @override
  Future<void> close() async {
    await _sync.close();
  }
}
