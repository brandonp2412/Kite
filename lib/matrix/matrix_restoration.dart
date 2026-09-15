import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/recoverable_file.dart';

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
    final contents = await RecoverableFile(file).readString();
    if (contents == null || contents.trim().isEmpty) return null;

    return Isolate.run<MatrixRestorationSnapshot?>(() {
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
    });
  }

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    final payload = await Isolate.run<String>(() {
      final document = <String, Object?>{
        'version': _schemaVersion,
        'accountId': snapshot.accountId,
        'navigationTarget': _encodeNavigationTarget(snapshot.navigationTarget),
      };
      return jsonEncode(document);
    });

    await RecoverableFile(file).replaceWithString(payload);
  }

  @override
  Future<void> clear() => RecoverableFile(file).clear();

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
    if (kind == MatrixNavigationKind.room.name && _isNonEmpty(roomId)) {
      return MatrixNavigationTarget.room(roomId as String);
    }
    if (kind == MatrixNavigationKind.event.name &&
        _isNonEmpty(roomId) &&
        _isNonEmpty(eventId)) {
      return MatrixNavigationTarget.event(roomId as String, eventId as String);
    }
    if (kind == MatrixNavigationKind.user.name && _isNonEmpty(userId)) {
      return MatrixNavigationTarget.user(userId as String);
    }
    if (kind == MatrixNavigationKind.invite.name && _isNonEmpty(roomId)) {
      return MatrixNavigationTarget.invite(roomId as String);
    }
    if (kind == MatrixNavigationKind.call.name && _isNonEmpty(roomId)) {
      return MatrixNavigationTarget.call(roomId as String);
    }
    return null;
  }

  static bool _isNonEmpty(Object? value) => value is String && value.isNotEmpty;
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
    final normalizedAccountId = accountId.trim();
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    return _enqueue(() {
      return _store.save(
        MatrixRestorationSnapshot(
          accountId: normalizedAccountId,
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
