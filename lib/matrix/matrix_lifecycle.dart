import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Lifecycle phases relevant to Matrix sync and lightweight process restore.
enum MatrixAppLifecyclePhase { foreground, background }

/// Minimal state Kite needs to restore the previous account/navigation context.
final class MatrixRestorationSnapshot {
  const MatrixRestorationSnapshot({
    required this.accountId,
    this.roomId,
    this.eventId,
  });

  final String accountId;
  final String? roomId;
  final String? eventId;

  Map<String, Object?> toJson() => <String, Object?>{
    'accountId': accountId,
    'roomId': roomId,
    'eventId': eventId,
  };

  static MatrixRestorationSnapshot fromJson(Map<String, Object?> json) {
    final accountId = json['accountId'];
    if (accountId is! String || accountId.isEmpty) {
      throw const FormatException('Missing accountId');
    }

    final roomId = json['roomId'];
    final eventId = json['eventId'];
    if (roomId != null && roomId is! String) {
      throw const FormatException('Invalid roomId');
    }
    if (eventId != null && eventId is! String) {
      throw const FormatException('Invalid eventId');
    }

    return MatrixRestorationSnapshot(
      accountId: accountId,
      roomId: roomId as String?,
      eventId: eventId as String?,
    );
  }
}

abstract interface class MatrixRestorationStore {
  Future<MatrixRestorationSnapshot?> load();

  Future<void> save(MatrixRestorationSnapshot snapshot);
}

/// Small persistent store for non-secret account/navigation restoration metadata.
///
/// Disk access is asynchronous and JSON encode/decode is isolated from the
/// Flutter UI isolate. Matrix credentials, crypto material, and decrypted
/// message contents must never be stored here.
final class FileMatrixRestorationStore implements MatrixRestorationStore {
  FileMatrixRestorationStore(this.file);

  final File file;

  @override
  Future<MatrixRestorationSnapshot?> load() async {
    if (!await file.exists()) return null;
    final encoded = await file.readAsString();
    final decoded = await Isolate.run<Object?>(() => jsonDecode(encoded));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid restoration snapshot');
    }
    return MatrixRestorationSnapshot.fromJson(decoded);
  }

  @override
  Future<void> save(MatrixRestorationSnapshot snapshot) async {
    final encoded = await Isolate.run<String>(
      () => jsonEncode(snapshot.toJson()),
    );
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    await temporary.rename(file.path);
  }
}

abstract interface class MatrixLifecycleSyncPort {
  Future<void> enterBackground();

  Future<void> enterForeground();
}

typedef RestorationSnapshotProvider = MatrixRestorationSnapshot Function();
typedef RestorationSnapshotConsumer = FutureOr<void> Function(
  MatrixRestorationSnapshot snapshot,
);

/// Serialises app lifecycle transitions so sync/store state cannot race.
///
/// Background transitions persist the latest restorable state before pausing
/// sync work. Foreground transitions resume sync only after any previous
/// background transition has completed. Duplicate phases are ignored.
final class MatrixLifecycleCoordinator {
  MatrixLifecycleCoordinator({
    required this.store,
    required this.syncPort,
    required this.currentSnapshot,
    required this.restoreSnapshot,
  });

  final MatrixRestorationStore store;
  final MatrixLifecycleSyncPort syncPort;
  final RestorationSnapshotProvider currentSnapshot;
  final RestorationSnapshotConsumer restoreSnapshot;

  MatrixAppLifecyclePhase _phase = MatrixAppLifecyclePhase.foreground;
  Future<void> _serial = Future<void>.value();

  MatrixAppLifecyclePhase get phase => _phase;

  Future<MatrixRestorationSnapshot?> restoreAfterProcessStart() async {
    final snapshot = await store.load();
    if (snapshot == null) return null;
    await restoreSnapshot(snapshot);
    return snapshot;
  }

  Future<bool> setPhase(MatrixAppLifecyclePhase next) {
    if (next == _phase) return Future<bool>.value(false);
    _phase = next;

    final completer = Completer<bool>();
    _serial = _serial.then((_) async {
      try {
        if (next == MatrixAppLifecyclePhase.background) {
          await store.save(currentSnapshot());
          await syncPort.enterBackground();
        } else {
          await syncPort.enterForeground();
        }
        completer.complete(true);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
