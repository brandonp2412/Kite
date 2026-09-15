import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_outbox.dart';
import 'package:kite/matrix/matrix_restoration.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';

void main() {
  group('MatrixOutbox', () {
    test(
      'keeps offline sends encrypted and flushes them on recovery',
      () async {
        final store = _FakeEncryptedOutboxStore();
        final transport = _FakeSendTransport();
        final outbox = MatrixOutbox(
          store: store,
          transport: transport,
          initialNetworkState: MatrixNetworkState.offline,
        );
        final transitions = <MatrixOutboxItem>[];
        final subscription = outbox.transitions.listen(transitions.add);
        final now = DateTime.utc(2026, 9, 15, 1);

        await outbox.hydrate(now: now);
        await outbox.enqueue(_message('local-1', 'txn-1'), now: now);

        expect(transport.sentTransactionIds, isEmpty);
        expect(store.pending.single.state, MatrixOutboxState.queuedOffline);

        await outbox.updateNetworkState(
          MatrixNetworkState.online,
          now: now.add(const Duration(seconds: 1)),
        );

        expect(transport.sentTransactionIds, <String>['txn-1']);
        expect(store.pending, isEmpty);
        expect(transitions.map((item) => item.state), <MatrixOutboxState>[
          MatrixOutboxState.queuedOffline,
          MatrixOutboxState.sending,
          MatrixOutboxState.sent,
        ]);
        expect(transitions.last.eventId, r'$sent-txn-1');

        await subscription.cancel();
        await outbox.close();
      },
    );

    test(
      'uses deterministic retry state before retrying a transient error',
      () async {
        final store = _FakeEncryptedOutboxStore();
        final transport = _FakeSendTransport(
          failures: <MatrixSendFailure>[
            const MatrixSendFailure(code: 'M_LIMIT_EXCEEDED', retryable: true),
          ],
        );
        final outbox = MatrixOutbox(
          store: store,
          transport: transport,
          initialNetworkState: MatrixNetworkState.online,
          retryDelay: (_) => const Duration(seconds: 5),
        );
        final now = DateTime.utc(2026, 9, 15, 1);

        await outbox.hydrate(now: now);
        await outbox.enqueue(_message('local-1', 'txn-1'), now: now);

        expect(transport.sentTransactionIds, <String>['txn-1']);
        expect(store.pending.single.state, MatrixOutboxState.retryScheduled);
        expect(store.pending.single.attempt, 1);
        expect(
          store.pending.single.nextRetryAt,
          now.add(const Duration(seconds: 5)),
        );
        expect(store.pending.single.failureCode, 'M_LIMIT_EXCEEDED');

        await outbox.retryDue(now.add(const Duration(seconds: 4)));
        expect(transport.sentTransactionIds, <String>['txn-1']);

        await outbox.retryDue(now.add(const Duration(seconds: 5)));
        expect(transport.sentTransactionIds, <String>['txn-1', 'txn-1']);
        expect(store.pending, isEmpty);
        await outbox.close();
      },
    );

    test('keeps permanent failures pending until explicit retry', () async {
      final store = _FakeEncryptedOutboxStore();
      final transport = _FakeSendTransport(
        failures: <MatrixSendFailure>[
          const MatrixSendFailure(code: 'M_FORBIDDEN', retryable: false),
        ],
      );
      final outbox = MatrixOutbox(
        store: store,
        transport: transport,
        initialNetworkState: MatrixNetworkState.online,
      );
      final now = DateTime.utc(2026, 9, 15, 1);

      await outbox.hydrate(now: now);
      await outbox.enqueue(_message('local-1', 'txn-1'), now: now);

      expect(store.pending.single.state, MatrixOutboxState.failedPermanent);
      expect(store.pending.single.failureCode, 'M_FORBIDDEN');
      expect(transport.sentTransactionIds, <String>['txn-1']);

      await outbox.retry('local-1', now: now.add(const Duration(seconds: 1)));
      expect(transport.sentTransactionIds, <String>['txn-1', 'txn-1']);
      expect(store.pending, isEmpty);
      await outbox.close();
    });

    test(
      'flushes restored pending sends immediately when startup is online',
      () async {
        final store = _FakeEncryptedOutboxStore(
          initial: <MatrixOutboxItem>[_message('local-1', 'txn-stable')],
        );
        final transport = _FakeSendTransport();
        final outbox = MatrixOutbox(
          store: store,
          transport: transport,
          initialNetworkState: MatrixNetworkState.online,
        );
        final now = DateTime.utc(2026, 9, 15, 1);

        await outbox.hydrate(now: now);

        expect(transport.sentTransactionIds, <String>['txn-stable']);
        expect(store.pending, isEmpty);
        await outbox.close();
      },
    );

    test(
      'recovers an interrupted send using the same transaction id',
      () async {
        final store = _FakeEncryptedOutboxStore(
          initial: <MatrixOutboxItem>[
            _message(
              'local-1',
              'txn-stable',
              state: MatrixOutboxState.sending,
              attempt: 1,
            ),
          ],
        );
        final transport = _FakeSendTransport();
        final outbox = MatrixOutbox(
          store: store,
          transport: transport,
          initialNetworkState: MatrixNetworkState.offline,
        );
        final now = DateTime.utc(2026, 9, 15, 1);

        await outbox.hydrate(now: now);
        expect(store.pending.single.state, MatrixOutboxState.queuedOffline);
        expect(store.pending.single.transactionId, 'txn-stable');

        await outbox.updateNetworkState(MatrixNetworkState.online, now: now);
        expect(transport.sentTransactionIds, <String>['txn-stable']);
        expect(store.pending, isEmpty);
        await outbox.close();
      },
    );

    test('close is terminal and cannot race a late queued send', () async {
      final store = _FakeEncryptedOutboxStore();
      final outbox = MatrixOutbox(
        store: store,
        transport: _FakeSendTransport(),
        initialNetworkState: MatrixNetworkState.offline,
      );
      final now = DateTime.utc(2026, 9, 15, 1);

      await outbox.hydrate(now: now);
      final closing = outbox.close();

      expect(
        () => outbox.enqueue(_message('late', 'txn-late'), now: now),
        throwsStateError,
      );
      expect(
        () => outbox.updateNetworkState(MatrixNetworkState.online, now: now),
        throwsStateError,
      );

      await closing;
      await outbox.close();
      expect(store.pending, isEmpty);
    });

    test('rejects plaintext outbox persistence', () {
      expect(
        () => MatrixOutbox(
          store: _FakeEncryptedOutboxStore(isEncryptedAtRest: false),
          transport: _FakeSendTransport(),
          initialNetworkState: MatrixNetworkState.offline,
        ),
        throwsStateError,
      );
    });
  });

  group('MatrixHomeserverDiscovery', () {
    test('uses m.homeserver base_url from client well-known', () async {
      final client = _FakeWellKnownClient(
        document: <String, Object?>{
          'm.homeserver': <String, Object?>{
            'base_url': 'https://matrix.example.org/client',
          },
        },
      );
      final discovery = MatrixHomeserverDiscovery(client);

      final result = await discovery.discover('example.org');

      expect(client.requestedUris, <Uri>[
        Uri.parse('https://example.org/.well-known/matrix/client'),
      ]);
      expect(result.enteredServer, Uri.parse('https://example.org'));
      expect(
        result.homeserverBaseUrl,
        Uri.parse('https://matrix.example.org/client'),
      );
      expect(result.usedWellKnown, isTrue);
    });

    test('falls back to entered server when well-known is absent', () async {
      final discovery = MatrixHomeserverDiscovery(_FakeWellKnownClient());

      final result = await discovery.discover('https://matrix.example.org');

      expect(result.homeserverBaseUrl, Uri.parse('https://matrix.example.org'));
      expect(result.usedWellKnown, isFalse);
    });

    test('rejects malformed well-known homeserver configuration', () async {
      final discovery = MatrixHomeserverDiscovery(
        _FakeWellKnownClient(
          document: <String, Object?>{
            'm.homeserver': <String, Object?>{'base_url': 'not a url'},
          },
        ),
      );

      await expectLater(
        discovery.discover('example.org'),
        throwsA(isA<MatrixHomeserverDiscoveryException>()),
      );
    });

    test(
      'rejects unsafe components in discovered homeserver base URLs',
      () async {
        for (final baseUrl in <String>[
          'https://user:secret@matrix.example.org',
          'https://matrix.example.org?token=secret',
          'https://matrix.example.org/#fragment',
        ]) {
          final discovery = MatrixHomeserverDiscovery(
            _FakeWellKnownClient(
              document: <String, Object?>{
                'm.homeserver': <String, Object?>{'base_url': baseUrl},
              },
            ),
          );

          await expectLater(
            discovery.discover('example.org'),
            throwsA(isA<MatrixHomeserverDiscoveryException>()),
            reason: baseUrl,
          );
        }
      },
    );
  });

  group('MatrixDeepLinkParser', () {
    const parser = MatrixDeepLinkParser();

    test('parses matrix.to room event user invite and call targets', () {
      expect(
        parser.parse(
          Uri.parse(
            'https://matrix.to/#/!room:example.org/\$event:example.org',
          ),
        ),
        const MatrixNavigationTarget.event(
          '!room:example.org',
          r'$event:example.org',
        ),
      );
      expect(
        parser.parse(Uri.parse('https://matrix.to/#/@alice:example.org')),
        const MatrixNavigationTarget.user('@alice:example.org'),
      );
      expect(
        parser.parse(
          Uri.parse('https://matrix.to/#/%23kite:example.org?action=join'),
        ),
        const MatrixNavigationTarget.invite('#kite:example.org'),
      );
      expect(
        parser.parse(
          Uri.parse('https://matrix.to/#/!room:example.org?action=call'),
        ),
        const MatrixNavigationTarget.call('!room:example.org'),
      );
    });

    test('parses matrix scheme targets and rejects unrelated links', () {
      expect(
        parser.parse(Uri.parse('matrix:u/alice:example.org')),
        const MatrixNavigationTarget.user('@alice:example.org'),
      );
      expect(
        parser.parse(
          Uri.parse('matrix:r/room:example.org/e/event:example.org'),
        ),
        const MatrixNavigationTarget.event(
          '!room:example.org',
          r'$event:example.org',
        ),
      );
      expect(parser.parse(Uri.parse('https://example.org/room')), isNull);
    });

    test('matrix scheme path segments are decoded exactly once', () {
      expect(
        parser.parse(Uri.parse('matrix:r/%2521literal:example.org')),
        const MatrixNavigationTarget.room('!%21literal:example.org'),
      );
    });

    test(
      'malformed matrix.to fragment encoding is rejected without throwing',
      () {
        expect(
          () => parser.parse(Uri.parse('https://matrix.to/#/%E0%A4%A')),
          returnsNormally,
        );
        expect(parser.parse(Uri.parse('https://matrix.to/#/%E0%A4%A')), isNull);
      },
    );
  });

  test(
    'deep-link router forwards typed targets and ignores unrelated links',
    () async {
      final routed = <MatrixNavigationTarget>[];
      final router = MatrixDeepLinkRouter(navigate: routed.add);

      expect(
        await router.route(
          Uri.parse('https://matrix.to/#/!room:example.org?action=call'),
        ),
        isTrue,
      );
      expect(routed, <MatrixNavigationTarget>[
        const MatrixNavigationTarget.call('!room:example.org'),
      ]);

      expect(
        await router.route(Uri.parse('https://example.org/room')),
        isFalse,
      );
      expect(routed, hasLength(1));
    },
  );

  test('restoration persists account and typed navigation state', () async {
    final store = _FakeRestorationStore();
    final coordinator = MatrixRestorationCoordinator(store);

    expect(await coordinator.restore(), isNull);

    await coordinator.record(
      accountId: '@alice:example.org',
      navigationTarget: const MatrixNavigationTarget.event(
        '!room:example.org',
        r'$event:example.org',
      ),
    );

    final restored = await coordinator.restore();
    expect(restored?.accountId, '@alice:example.org');
    expect(
      restored?.navigationTarget,
      const MatrixNavigationTarget.event(
        '!room:example.org',
        r'$event:example.org',
      ),
    );

    await coordinator.clear();
    expect(await coordinator.restore(), isNull);
  });
}

MatrixOutboxItem _message(
  String localId,
  String transactionId, {
  MatrixOutboxState state = MatrixOutboxState.queuedOffline,
  int attempt = 0,
}) {
  return MatrixOutboxItem(
    localId: localId,
    roomId: '!room:example.org',
    transactionId: transactionId,
    eventType: 'm.room.message',
    content: const <String, Object?>{'msgtype': 'm.text', 'body': 'Hello'},
    state: state,
    attempt: attempt,
  );
}

final class _FakeWellKnownClient implements MatrixWellKnownClient {
  _FakeWellKnownClient({this.document});

  final Map<String, Object?>? document;
  final List<Uri> requestedUris = <Uri>[];

  @override
  Future<Map<String, Object?>?> fetchClientConfiguration(Uri uri) async {
    requestedUris.add(uri);
    return document;
  }
}

final class _FakeEncryptedOutboxStore implements MatrixEncryptedOutboxStore {
  _FakeEncryptedOutboxStore({
    this.isEncryptedAtRest = true,
    List<MatrixOutboxItem> initial = const <MatrixOutboxItem>[],
  }) : pending = List<MatrixOutboxItem>.of(initial);

  @override
  final bool isEncryptedAtRest;

  List<MatrixOutboxItem> pending;

  @override
  Future<List<MatrixOutboxItem>> loadPending() async {
    return List<MatrixOutboxItem>.of(pending);
  }

  @override
  Future<void> replacePending(List<MatrixOutboxItem> items) async {
    pending = List<MatrixOutboxItem>.of(items);
  }
}

final class _FakeSendTransport implements MatrixSendTransport {
  _FakeSendTransport({List<MatrixSendFailure> failures = const []})
    : _failures = List<MatrixSendFailure>.of(failures);

  final List<MatrixSendFailure> _failures;
  final List<String> sentTransactionIds = <String>[];

  @override
  Future<MatrixSendReceipt> send(MatrixOutboxItem item) async {
    sentTransactionIds.add(item.transactionId);
    if (_failures.isNotEmpty) throw _failures.removeAt(0);
    return MatrixSendReceipt(eventId: '\$sent-${item.transactionId}');
  }
}

final class _FakeRestorationStore implements MatrixRestorationStore {
  MatrixRestorationSnapshot? snapshot;

  @override
  Future<void> clear() async {
    snapshot = null;
  }

  @override
  Future<MatrixRestorationSnapshot?> load() async => snapshot;

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
