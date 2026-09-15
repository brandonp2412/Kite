import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

final class _FakeAccountManagementGateway implements AccountManagementGateway {
  List<ManagedMatrixAccount> loaded = const <ManagedMatrixAccount>[];
  Object? loadError;
  Object? activateError;
  Object? signOutError;
  Completer<void>? activateCompleter;
  int loadCalls = 0;
  final activatedAccountIds = <String>[];
  final signedOutAccountIds = <String>[];

  @override
  Future<void> activateAccount(String accountId) async {
    activatedAccountIds.add(accountId);
    if (activateError case final error?) throw error;
    final completer = activateCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async {
    loadCalls += 1;
    if (loadError case final error?) throw error;
    return loaded;
  }

  @override
  Future<void> signOutAccount(String accountId) async {
    signedOutAccountIds.add(accountId);
    if (signOutError case final error?) throw error;
  }
}

AuthenticatedSession _session({
  required String userId,
  required String deviceId,
  required String homeserver,
}) {
  return AuthenticatedSession(
    userId: userId,
    deviceId: deviceId,
    homeserver: HomeserverAddress.parse(homeserver),
  );
}

ManagedMatrixAccount _account({
  required String accountId,
  required String userId,
  required String deviceId,
  required String homeserver,
  bool isActive = false,
}) {
  return ManagedMatrixAccount(
    accountId: accountId,
    session: _session(
      userId: userId,
      deviceId: deviceId,
      homeserver: homeserver,
    ),
    isActive: isActive,
  );
}

void main() {
  test(
    'loads isolated account metadata and identifies the active account',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
          _account(
            accountId: 'personal',
            userId: '@alice:example.org',
            deviceId: 'PERSONAL_DEVICE',
            homeserver: 'example.org',
          ),
        ];
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.load(), isTrue);
      expect(controller.accounts.value, hasLength(2));
      expect(controller.activeAccount?.accountId, 'work');
      expect(controller.needsAccountSelection, isFalse);
    },
  );

  test(
    'switches account only after the gateway activates its isolated store',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
          _account(
            accountId: 'personal',
            userId: '@alice:example.org',
            deviceId: 'PERSONAL_DEVICE',
            homeserver: 'example.org',
          ),
        ];
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.activate('personal'), isTrue);
      expect(gateway.activatedAccountIds, <String>['personal']);
      expect(controller.activeAccount?.accountId, 'personal');

      gateway.activateError = StateError('access_token=secret');
      expect(await controller.activate('work'), isFalse);
      expect(controller.activeAccount?.accountId, 'personal');
      expect(controller.errorMessage.value, 'Kite could not switch accounts.');
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test('serializes account mutations across isolated stores', () async {
    final activation = Completer<void>();
    final gateway = _FakeAccountManagementGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'work',
          userId: '@alice:work.example.org',
          deviceId: 'WORK_DEVICE',
          homeserver: 'work.example.org',
          isActive: true,
        ),
        _account(
          accountId: 'personal',
          userId: '@alice:example.org',
          deviceId: 'PERSONAL_DEVICE',
          homeserver: 'example.org',
        ),
      ]
      ..activateCompleter = activation;
    final controller = AccountManagementController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    final switching = controller.activate('personal');
    await Future<void>.delayed(Duration.zero);
    expect(controller.busyAccountIds.value, <String>{'personal'});

    expect(await controller.signOut('work'), isFalse);
    expect(gateway.signedOutAccountIds, isEmpty);
    expect(controller.activeAccount?.accountId, 'work');

    activation.complete();
    expect(await switching, isTrue);
    expect(controller.activeAccount?.accountId, 'personal');
  });

  test('account refresh cannot race an in-flight account switch', () async {
    final activation = Completer<void>();
    final gateway = _FakeAccountManagementGateway()
      ..loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'work',
          userId: '@alice:work.example.org',
          deviceId: 'WORK_DEVICE',
          homeserver: 'work.example.org',
          isActive: true,
        ),
        _account(
          accountId: 'personal',
          userId: '@alice:example.org',
          deviceId: 'PERSONAL_DEVICE',
          homeserver: 'example.org',
        ),
      ]
      ..activateCompleter = activation;
    final controller = AccountManagementController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    expect(gateway.loadCalls, 1);

    final switching = controller.activate('personal');
    await Future<void>.delayed(Duration.zero);
    expect(controller.busyAccountIds.value, <String>{'personal'});

    gateway.loaded = <ManagedMatrixAccount>[
      _account(
        accountId: 'work',
        userId: '@alice:work.example.org',
        deviceId: 'WORK_DEVICE',
        homeserver: 'work.example.org',
        isActive: true,
      ),
    ];
    expect(await controller.load(), isFalse);
    expect(gateway.loadCalls, 1);
    expect(controller.accounts.value, hasLength(2));

    activation.complete();
    expect(await switching, isTrue);
    expect(controller.activeAccount?.accountId, 'personal');
  });

  test(
    'sign out removes only the selected account after gateway success',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
          _account(
            accountId: 'personal',
            userId: '@alice:example.org',
            deviceId: 'PERSONAL_DEVICE',
            homeserver: 'example.org',
          ),
        ];
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.signOut('personal'), isTrue);
      expect(gateway.signedOutAccountIds, <String>['personal']);
      expect(
        controller.accounts.value.map((account) => account.accountId),
        <String>['work'],
      );
      expect(controller.activeAccount?.accountId, 'work');
    },
  );

  test(
    'signing out the active account requires explicit selection of a survivor',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
          _account(
            accountId: 'personal',
            userId: '@alice:example.org',
            deviceId: 'PERSONAL_DEVICE',
            homeserver: 'example.org',
          ),
        ];
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.signOut('work'), isTrue);
      expect(controller.activeAccount, isNull);
      expect(controller.needsAccountSelection, isTrue);
      expect(controller.accounts.value.single.accountId, 'personal');
    },
  );

  test(
    'failed sign out keeps account state intact and redacts failures',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
        ]
        ..signOutError = StateError('recovery_key=secret');
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.signOut('work'), isFalse);
      expect(controller.accounts.value.single.accountId, 'work');
      expect(controller.activeAccount?.accountId, 'work');
      expect(
        controller.errorMessage.value,
        'Kite could not sign out that account.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'load failure preserves known accounts for offline-first rendering',
    () async {
      final gateway = _FakeAccountManagementGateway()
        ..loaded = <ManagedMatrixAccount>[
          _account(
            accountId: 'work',
            userId: '@alice:work.example.org',
            deviceId: 'WORK_DEVICE',
            homeserver: 'work.example.org',
            isActive: true,
          ),
        ];
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      gateway.loadError = StateError('access_token=secret');
      expect(await controller.load(), isFalse);

      expect(controller.accounts.value.single.accountId, 'work');
      expect(controller.activeAccount?.accountId, 'work');
      expect(
        controller.errorMessage.value,
        'Kite could not load your accounts.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'rejects duplicate, malformed, and ambiguous account metadata',
    () async {
      final gateway = _FakeAccountManagementGateway();
      final controller = AccountManagementController(gateway);
      addTearDown(controller.dispose);

      gateway.loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'duplicate',
          userId: '@alice:example.org',
          deviceId: 'ONE',
          homeserver: 'example.org',
          isActive: true,
        ),
        _account(
          accountId: 'duplicate',
          userId: '@bob:example.org',
          deviceId: 'TWO',
          homeserver: 'example.org',
        ),
      ];
      expect(await controller.load(), isFalse);

      gateway.loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'one',
          userId: '@alice:example.org',
          deviceId: 'ONE',
          homeserver: 'example.org',
          isActive: true,
        ),
        _account(
          accountId: 'two',
          userId: '@bob:example.org',
          deviceId: 'TWO',
          homeserver: 'example.org',
          isActive: true,
        ),
      ];
      expect(await controller.load(), isFalse);

      gateway.loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'bad-user',
          userId: 'alice',
          deviceId: 'ONE',
          homeserver: 'example.org',
          isActive: true,
        ),
      ];
      expect(await controller.load(), isFalse);

      gateway.loaded = <ManagedMatrixAccount>[
        _account(
          accountId: 'bad-device',
          userId: '@alice:example.org',
          deviceId: ' DEVICE ',
          homeserver: 'example.org',
          isActive: true,
        ),
      ];
      expect(await controller.load(), isFalse);

      expect(
        controller.errorMessage.value,
        'Kite received invalid account information.',
      );
    },
  );

  test('unknown account ids never reach the gateway', () async {
    final gateway = _FakeAccountManagementGateway();
    final controller = AccountManagementController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.activate('missing'), isFalse);
    expect(await controller.signOut('missing'), isFalse);
    expect(gateway.activatedAccountIds, isEmpty);
    expect(gateway.signedOutAccountIds, isEmpty);
    expect(
      controller.errorMessage.value,
      'That Kite account is no longer available.',
    );
  });
}
