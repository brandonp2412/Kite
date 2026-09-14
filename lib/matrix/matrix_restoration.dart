import 'package:kite/matrix/matrix_navigation.dart';

final class MatrixRestorationSnapshot {
  const MatrixRestorationSnapshot({
    required this.accountId,
    required this.navigationTarget,
  });

  final String accountId;
  final MatrixNavigationTarget navigationTarget;
}

abstract interface class MatrixRestorationStore {
  Future<MatrixRestorationSnapshot?> load();

  Future<void> save(MatrixRestorationSnapshot snapshot);

  Future<void> clear();
}

final class MatrixRestorationCoordinator {
  MatrixRestorationCoordinator(this._store);

  final MatrixRestorationStore _store;
  Future<void> _transition = Future<void>.value();

  Future<MatrixRestorationSnapshot?> restore() async {
    await _transition;
    return _store.load();
  }

  Future<void> record({
    required String accountId,
    required MatrixNavigationTarget navigationTarget,
  }) {
    if (accountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    return _enqueue(() {
      return _store.save(
        MatrixRestorationSnapshot(
          accountId: accountId,
          navigationTarget: navigationTarget,
        ),
      );
    });
  }

  Future<void> clear() => _enqueue(_store.clear);

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _transition.then<void>(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
