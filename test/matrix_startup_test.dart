import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_deep_link.dart';
import 'package:kite/matrix/matrix_startup.dart';

void main() {
  test(
    'queues cold-start deep links until session restoration completes',
    () async {
      final restoreGate = Completer<void>();
      final events = <String>[];
      final coordinator = MatrixStartupCoordinator(
        restoreSession: () async {
          events.add('restore-start');
          await restoreGate.future;
          events.add('restore-end');
        },
        dispatchDeepLink: (link) => events.add('route:${link.targetId}'),
      );

      expect(
        await coordinator.submitDeepLink(
          'matrix:roomid/one:example.org?via=example.org',
        ),
        isTrue,
      );
      final startup = coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(
        await coordinator.submitDeepLink(
          'matrix:u/alice:example.org?action=chat',
        ),
        isTrue,
      );

      expect(events, <String>['restore-start']);
      expect(coordinator.pendingLinkCount, 2);
      expect(coordinator.isReady, isFalse);

      restoreGate.complete();
      await startup;

      expect(events, <String>[
        'restore-start',
        'restore-end',
        'route:!one:example.org',
        'route:@alice:example.org',
      ]);
      expect(coordinator.pendingLinkCount, 0);
      expect(coordinator.isReady, isTrue);
    },
  );

  test(
    'warm deep links dispatch immediately through the same router',
    () async {
      final routed = <MatrixDeepLink>[];
      final coordinator = MatrixStartupCoordinator(
        restoreSession: () async {},
        dispatchDeepLink: routed.add,
      );

      await coordinator.start();
      expect(
        await coordinator.submitDeepLink(
          'https://matrix.to/#/%21room%3Aexample.org/%24event',
        ),
        isTrue,
      );

      expect(routed, hasLength(1));
      expect(routed.single.kind, MatrixDeepLinkKind.event);
      expect(routed.single.targetId, '!room:example.org');
      expect(routed.single.eventId, r'$event');
    },
  );

  test('concurrent start calls share one restoration', () async {
    final restoreGate = Completer<void>();
    var restoreCalls = 0;
    final coordinator = MatrixStartupCoordinator(
      restoreSession: () async {
        restoreCalls += 1;
        await restoreGate.future;
      },
      dispatchDeepLink: (_) {},
    );

    final first = coordinator.start();
    final second = coordinator.start();
    await Future<void>.delayed(Duration.zero);

    expect(restoreCalls, 1);
    restoreGate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(coordinator.isReady, isTrue);
  });

  test('failed restoration keeps pending links for a later retry', () async {
    var fail = true;
    final routed = <String>[];
    final coordinator = MatrixStartupCoordinator(
      restoreSession: () async {
        if (fail) throw StateError('restore failed');
      },
      dispatchDeepLink: (link) => routed.add(link.targetId),
    );

    await coordinator.submitDeepLink('matrix:u/alice:example.org');
    await expectLater(coordinator.start(), throwsStateError);

    expect(coordinator.isReady, isFalse);
    expect(coordinator.pendingLinkCount, 1);
    expect(routed, isEmpty);

    fail = false;
    await coordinator.start();
    expect(coordinator.isReady, isTrue);
    expect(coordinator.pendingLinkCount, 0);
    expect(routed, <String>['@alice:example.org']);
  });

  test('invalid inbound links never enter the startup queue', () async {
    final coordinator = MatrixStartupCoordinator(
      restoreSession: () async {},
      dispatchDeepLink: (_) {},
    );

    expect(
      await coordinator.submitDeepLink('https://example.org/nope'),
      isFalse,
    );
    expect(coordinator.pendingLinkCount, 0);
  });
}
