import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/calls/call_deep_link_coordinator.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/calls/matrix_call_deep_link.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/testing/deterministic_call_adapter.dart';
import 'package:kite/testing/deterministic_routing_adapters.dart';

void main() {
  test(
    'Matrix call deep link resolves active MatrixRTC identity before opening',
    () async {
      final accounts = FakeAccountActivationPort('work');
      final navigation = FakeAppNavigationPort();
      final resolver = DeterministicMatrixCallDeepLinkResolver()
        ..descriptor = const MatrixRtcSessionDescriptor(
          callId: 'rtc-42',
          roomId: '!calls:example.org',
          kind: KiteCallKind.video,
          scope: KiteCallScope.group,
        );
      final coordinator = _coordinator(accounts, navigation, resolver);

      final result = await coordinator.open(
        const MatrixNavigationTarget.call('!calls:example.org'),
      );

      expect(result, MatrixCallDeepLinkResult.opened);
      expect(resolver.resolutions.single.accountId, 'work');
      expect(resolver.resolutions.single.roomIdOrAlias, '!calls:example.org');
      expect(accounts.activations, isEmpty);
      expect(navigation.opened, <AppDestination>[
        const AppDestination.call(
          accountId: 'work',
          roomId: '!calls:example.org',
          callId: 'rtc-42',
        ),
      ]);
    },
  );

  test('room aliases may resolve to a concrete Matrix room call', () async {
    final accounts = FakeAccountActivationPort('work');
    final navigation = FakeAppNavigationPort();
    final resolver = DeterministicMatrixCallDeepLinkResolver()
      ..descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-alias',
        roomId: '!resolved:example.org',
        kind: KiteCallKind.voice,
        scope: KiteCallScope.group,
      );
    final coordinator = _coordinator(accounts, navigation, resolver);

    expect(
      await coordinator.open(
        const MatrixNavigationTarget.call('#team:example.org'),
      ),
      MatrixCallDeepLinkResult.opened,
    );
    expect(
      navigation.opened.single,
      const AppDestination.call(
        accountId: 'work',
        roomId: '!resolved:example.org',
        callId: 'rtc-alias',
      ),
    );
  });

  test('stale and non-call links never navigate', () async {
    final accounts = FakeAccountActivationPort('work');
    final navigation = FakeAppNavigationPort();
    final resolver = DeterministicMatrixCallDeepLinkResolver();
    final coordinator = _coordinator(accounts, navigation, resolver);

    expect(
      await coordinator.open(
        const MatrixNavigationTarget.call('!calls:example.org'),
      ),
      MatrixCallDeepLinkResult.noActiveCall,
    );
    expect(
      await coordinator.open(
        const MatrixNavigationTarget.room('!room:example.org'),
      ),
      MatrixCallDeepLinkResult.notCallTarget,
    );
    expect(navigation.opened, isEmpty);
    expect(resolver.resolutions, hasLength(1));
  });

  test('resolved call cannot redirect an exact room-id deep link', () async {
    final accounts = FakeAccountActivationPort('work');
    final navigation = FakeAppNavigationPort();
    final resolver = DeterministicMatrixCallDeepLinkResolver()
      ..descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-wrong',
        roomId: '!other:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.group,
      );
    final coordinator = _coordinator(accounts, navigation, resolver);

    await expectLater(
      coordinator.open(const MatrixNavigationTarget.call('!calls:example.org')),
      throwsStateError,
    );
    expect(navigation.opened, isEmpty);
  });

  test(
    'call deep links require an active account before SDK resolution',
    () async {
      final accounts = FakeAccountActivationPort();
      final navigation = FakeAppNavigationPort();
      final resolver = DeterministicMatrixCallDeepLinkResolver();
      final coordinator = _coordinator(accounts, navigation, resolver);

      await expectLater(
        coordinator.open(
          const MatrixNavigationTarget.call('!calls:example.org'),
        ),
        throwsStateError,
      );
      expect(resolver.resolutions, isEmpty);
      expect(navigation.opened, isEmpty);
    },
  );

  test('stale call resolution cannot reactivate an old account', () async {
    final accounts = FakeAccountActivationPort('work');
    final navigation = FakeAppNavigationPort();
    final resolver = DeterministicMatrixCallDeepLinkResolver()
      ..descriptor = const MatrixRtcSessionDescriptor(
        callId: 'rtc-work',
        roomId: '!work:example.org',
        kind: KiteCallKind.video,
        scope: KiteCallScope.group,
      )
      ..holdNextResolution = true;
    final coordinator = _coordinator(accounts, navigation, resolver);

    final staleOpen = coordinator.open(
      const MatrixNavigationTarget.call('!work:example.org'),
    );
    while (!resolver.hasHeldResolution) {
      await Future<void>.delayed(Duration.zero);
    }

    await accounts.activateAccount('personal');
    resolver.descriptor = const MatrixRtcSessionDescriptor(
      callId: 'rtc-personal',
      roomId: '!personal:example.org',
      kind: KiteCallKind.voice,
      scope: KiteCallScope.group,
    );
    final currentResult = await coordinator.open(
      const MatrixNavigationTarget.call('!personal:example.org'),
    );
    resolver.releaseHeldResolution();

    expect(await staleOpen, MatrixCallDeepLinkResult.superseded);
    expect(currentResult, MatrixCallDeepLinkResult.opened);
    expect(accounts.activeAccountId, 'personal');
    expect(accounts.activations, <String>['personal']);
    expect(navigation.opened, <AppDestination>[
      const AppDestination.call(
        accountId: 'personal',
        roomId: '!personal:example.org',
        callId: 'rtc-personal',
      ),
    ]);
  });
}

MatrixCallDeepLinkCoordinator _coordinator(
  FakeAccountActivationPort accounts,
  FakeAppNavigationPort navigation,
  DeterministicMatrixCallDeepLinkResolver resolver,
) => MatrixCallDeepLinkCoordinator(
  accounts: accounts,
  resolver: resolver,
  calls: CallDeepLinkCoordinator(accounts: accounts, navigation: navigation),
);
