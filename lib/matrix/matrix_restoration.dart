import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

final class FileMatrixRestorationStore implements MatrixRestorationStore {
  FileMatrixRestorationStore(this.file);

  static const int _schemaVersion = 1;

  final File file;

  @override
  Future<MatrixRestorationSnapshot?> load() async {
    if (!await file.exists()) return null;

    final contents = await file.readAsString();
    if (contents.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != _schemaVersion) return null;

      final accountId = decoded['accountId'];
      final target = decoded['navigationTarget'];
      if (accountId is! String || accountId.isEmpty || target is! Map) {
        return null;
      }

      final navigationTarget = _decodeNavigationTarget(
        Map<String, dynamic>.from(target),
      );
      if (navigationTarget == null) return null;

      return MatrixRestorationSnapshot(
        accountId: accountId,
        navigationTarget: navigationTarget,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final payload = jsonEncode(<String, Object?>{
      'version': _schemaVersion,
      'accountId': snapshot.accountId,
      'navigationTarget': _encodeNavigationTarget(snapshot.navigationTarget),
    });

    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    if (await file.exists()) await file.delete();
  }

  static Map<String, Object?> _encodeNavigationTarget(
    MatrixNavigationTarget target,
  ) {
    final payload = <String, Object?>{'kind': target.kind.name};
    final roomId = target.roomIdOrAlias;
    final eventId = target.eventId;
    final userId = target.userId;
    if (roomId != null) payload['roomIdOrAlias'] = roomId;
    if (eventId != null) payload['eventId'] = eventId;
    if (userId != null) payload['userId'] = userId;
    return payload;
  }

  static MatrixNavigationTarget? _decodeNavigationTarget(
    Map<String, dynamic> payload,
  ) {
    final kind = payload['kind'];
    final roomId = payload['roomIdOrAlias'];
    final eventId = payload['eventId'];
    final userId = payload['userId'];

    if (kind == MatrixNavigationKind.home.name) {
      return const MatrixNavigationTarget.home();
    }
    if (kind == MatrixNavigationKind.room.name && roomId is String) {
      return MatrixNavigationTarget.room(roomId);
    }
    if (kind == MatrixNavigationKind.event.name &&
        roomId is String &&
        eventId is String) {
      return MatrixNavigationTarget.event(roomId, eventId);
    }
    if (kind == MatrixNavigationKind.user.name && userId is String) {
      return MatrixNavigationTarget.user(userId);
    }
    if (kind == MatrixNavigationKind.invite.name && roomId is String) {
      return MatrixNavigationTarget.invite(roomId);
    }
    if (kind == MatrixNavigationKind.call.name && roomId is String) {
      return MatrixNavigationTarget.call(roomId);
    }
    return null;
  }
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

typedef MatrixRestorationAccountAvailable = FutureOr<bool> Function(
  String accountId,
);
typedef MatrixRestorationAccountActivator = FutureOr<void> Function(
  String accountId,
);

final class MatrixProcessRestorationCoordinator {
  const MatrixProcessRestorationCoordinator({
    required this.restoration,
    required this.isAccountAvailable,
    required this.activateAccount,
    required this.navigate,
  });

  final MatrixRestorationCoordinator restoration;
  final MatrixRestorationAccountAvailable isAccountAvailable;
  final MatrixRestorationAccountActivator activateAccount;
  final MatrixNavigationHandler navigate;

  Future<bool> restore() async {
    final snapshot = await restoration.restore();
    if (snapshot == null) return false;

    if (!await isAccountAvailable(snapshot.accountId)) {
      await restoration.clear();
      return false;
    }

    await activateAccount(snapshot.accountId);
    await navigate(snapshot.navigationTarget);
    return true;
  }
}
