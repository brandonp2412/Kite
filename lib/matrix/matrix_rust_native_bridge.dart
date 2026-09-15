import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

const int kiteMatrixNativeAbiVersion = 5;

const Duration _matrixRustSyncPollTimeout = Duration(seconds: 5);
const int _matrixRustMaxRetryDelaySeconds = 30;

Duration _matrixRustRetryDelayForAttempt(int attempt) {
  var seconds = 1;
  for (var index = 1; index < attempt; index += 1) {
    if (seconds >= _matrixRustMaxRetryDelaySeconds) break;
    seconds *= 2;
    if (seconds > _matrixRustMaxRetryDelaySeconds) {
      seconds = _matrixRustMaxRetryDelaySeconds;
    }
  }
  return Duration(seconds: seconds);
}

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _ClientNewNative = Pointer<Void> Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientNewDart = Pointer<Void> Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSyncOnceNative = Pointer<Char> Function(
  Pointer<Void>,
  Uint64,
  Pointer<Char>,
  Uint64,
);
typedef _ClientSyncOnceDart = Pointer<Char> Function(
  Pointer<Void>,
  int,
  Pointer<Char>,
  int,
);
typedef _ClientPaginateNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _ClientPaginateDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _StringFreeNative = Void Function(Pointer<Char> value);
typedef _StringFreeDart = void Function(Pointer<Char> value);
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

typedef MatrixSdkStoreSecretResolver = Future<String> Function(String keyId);
typedef MatrixRustSyncDelay = Future<void> Function(Duration duration);

final class _MatrixNativeSyncOperation {
  const _MatrixNativeSyncOperation({
    required this.libraryPath,
    required this.address,
    required this.timeoutMs,
    required this.since,
    required this.timelineEventLimit,
  });

  final String libraryPath;
  final int address;
  final int timeoutMs;
  final String? since;
  final int timelineEventLimit;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final syncOnce = library
        .lookupFunction<_ClientSyncOnceNative, _ClientSyncOnceDart>(
          'kite_matrix_client_sync_once',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final sinceUtf8 = since?.toNativeUtf8(allocator: calloc);
    try {
      final value = syncOnce(
        Pointer<Void>.fromAddress(address),
        timeoutMs,
        sinceUtf8 == null
            ? Pointer<Char>.fromAddress(0)
            : sinceUtf8.cast<Char>(),
        timelineEventLimit,
      );
      if (value == nullptr) {
        throw StateError('Matrix Rust SDK sync failed');
      }
      try {
        return value.cast<Utf8>().toDartString();
      } finally {
        freeString(value);
      }
    } finally {
      if (sinceUtf8 != null) calloc.free(sinceUtf8);
    }
  }
}

final class _MatrixNativePaginateOperation {
  const _MatrixNativePaginateOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
  });

  final String libraryPath;
  final int address;
  final String roomId;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final paginate = library
        .lookupFunction<_ClientPaginateNative, _ClientPaginateDart>(
          'kite_matrix_client_paginate_backwards',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final value = paginate(
        Pointer<Void>.fromAddress(address),
        roomIdUtf8.cast<Char>(),
      );
      if (value == nullptr) {
        throw StateError('Matrix Rust SDK back-pagination failed');
      }
      try {
        return value.cast<Utf8>().toDartString();
      } finally {
        freeString(value);
      }
    } finally {
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeSyncDecodeOperation {
  const _MatrixNativeSyncDecodeOperation(this.payload);

  final String payload;

  MatrixRustSyncDecodeResult call() {
    return MatrixRustSyncCodec().decodeSync(payload);
  }
}

final class _MatrixNativePaginationDecodeOperation {
  const _MatrixNativePaginationDecodeOperation(this.payload);

  final String payload;

  MatrixRustPaginationDecodeResult call() {
    return MatrixRustSyncCodec().decodePagination(payload);
  }
}

abstract interface class MatrixRustCodecExecutor {
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload);

  Future<MatrixRustPaginationDecodeResult> decodePagination(String payload);
}

final class IsolateMatrixRustCodecExecutor implements MatrixRustCodecExecutor {
  const IsolateMatrixRustCodecExecutor();

  @override
  Future<MatrixRustSyncDecodeResult> decodeSync(String payload) {
    return Isolate.run<MatrixRustSyncDecodeResult>(
      _MatrixNativeSyncDecodeOperation(payload).call,
    );
  }

  @override
  Future<MatrixRustPaginationDecodeResult> decodePagination(String payload) {
    return Isolate.run<MatrixRustPaginationDecodeResult>(
      _MatrixNativePaginationDecodeOperation(payload).call,
    );
  }
}

final class _MatrixNativeFreeOperation {
  const _MatrixNativeFreeOperation({
    required this.libraryPath,
    required this.address,
  });

  final String libraryPath;
  final int address;

  void call() {
    final library = DynamicLibrary.open(libraryPath);
    final clientFree = library
        .lookupFunction<_ClientFreeNative, _ClientFreeDart>(
          'kite_matrix_client_free',
        );
    clientFree(Pointer<Void>.fromAddress(address));
  }
}

abstract interface class MatrixRustBridge {
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  });
}

abstract interface class MatrixRustClient {
  bool get isClosed;

  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  });

  Future<String> paginateBackwards({required String roomId});

  Future<void> close();
}

final class MatrixRustNativeBridge implements MatrixRustBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

  @override
  Future<MatrixRustNativeClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  }) async {
    if (storePath.trim().isEmpty) {
      throw ArgumentError.value(storePath, 'storePath', 'must not be empty');
    }
    if (storePassphrase.isEmpty) {
      throw ArgumentError.value(
        storePassphrase,
        'storePassphrase',
        'must not be empty',
      );
    }
    if (storePath.contains('\u0000')) {
      throw ArgumentError.value(
        storePath,
        'storePath',
        'must not contain NUL bytes',
      );
    }
    if (storePassphrase.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'storePassphrase',
        'must not contain NUL bytes',
      );
    }

    final path = libraryPath;
    final homeserverText = homeserver.toString();
    final address = await Isolate.run<int>(() {
      final library = DynamicLibrary.open(path);
      final abiVersion = library
          .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
            'kite_matrix_abi_version',
          );
      if (abiVersion() != kiteMatrixNativeAbiVersion) {
        throw StateError('Unsupported Kite Matrix native ABI');
      }

      final clientNew = library
          .lookupFunction<_ClientNewNative, _ClientNewDart>(
            'kite_matrix_client_new',
          );
      final homeserverUtf8 = homeserverText.toNativeUtf8(allocator: calloc);
      final storePathUtf8 = storePath.toNativeUtf8(allocator: calloc);
      final passphraseUtf8 = storePassphrase.toNativeUtf8(allocator: calloc);
      final passphraseBytePointer = passphraseUtf8.cast<Uint8>();
      var passphraseByteLength = 0;
      while (passphraseBytePointer[passphraseByteLength] != 0) {
        passphraseByteLength += 1;
      }
      final passphraseBytes = passphraseBytePointer.asTypedList(
        passphraseByteLength + 1,
      );
      try {
        final client = clientNew(
          homeserverUtf8.cast<Char>(),
          storePathUtf8.cast<Char>(),
          passphraseUtf8.cast<Char>(),
        );
        if (client == nullptr) {
          throw StateError(
            'Matrix Rust SDK encrypted client construction failed',
          );
        }
        return client.address;
      } finally {
        passphraseBytes.fillRange(0, passphraseBytes.length, 0);
        calloc.free(passphraseUtf8);
        calloc.free(storePathUtf8);
        calloc.free(homeserverUtf8);
      }
    });

    return MatrixRustNativeClient._(libraryPath, address);
  }
}

final class MatrixRustNativeClient implements MatrixRustClient {
  MatrixRustNativeClient._(this.libraryPath, this._address);

  final String libraryPath;
  int _address;
  Future<void> _transition = Future<void>.value();

  @override
  bool get isClosed => _address == 0;

  @override
  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  }) {
    if (timeout.isNegative) {
      return Future<String>.error(
        ArgumentError.value(timeout, 'timeout', 'must not be negative'),
      );
    }
    if (timelineEventLimit <= 0) {
      return Future<String>.error(
        ArgumentError.value(
          timelineEventLimit,
          'timelineEventLimit',
          'must be positive',
        ),
      );
    }
    if (since != null && (since.isEmpty || since.contains('\u0000'))) {
      return Future<String>.error(
        ArgumentError.value(
          since,
          'since',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<String>(() async {
      final address = _requireAddress();
      final path = libraryPath;
      final timeoutMs = timeout.inMilliseconds;
      return Isolate.run<String>(
        _MatrixNativeSyncOperation(
          libraryPath: path,
          address: address,
          timeoutMs: timeoutMs,
          since: since,
          timelineEventLimit: timelineEventLimit,
        ).call,
      );
    });
  }

  @override
  Future<String> paginateBackwards({required String roomId}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<String>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<String>(() async {
      final address = _requireAddress();
      final path = libraryPath;
      return Isolate.run<String>(
        _MatrixNativePaginateOperation(
          libraryPath: path,
          address: address,
          roomId: normalizedRoomId,
        ).call,
      );
    });
  }

  @override
  Future<void> close() {
    return _enqueue<void>(() async {
      if (_address == 0) return;
      final address = _address;
      final path = libraryPath;
      await Isolate.run<void>(
        _MatrixNativeFreeOperation(libraryPath: path, address: address).call,
      );
      _address = 0;
    });
  }

  int _requireAddress() {
    final address = _address;
    if (address == 0) {
      throw StateError('Matrix Rust SDK client is closed');
    }
    return address;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _transition.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace _) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }
}

final class MatrixRustSdkBoundary implements MatrixSdkBoundary {
  MatrixRustSdkBoundary({
    required this.bridge,
    required this.homeserver,
    required this.resolveStoreSecret,
    MatrixRustCodecExecutor? codecExecutor,
    MatrixRustSyncDelay? syncRetryDelay,
    this.logger,
    this.crashReporter,
  }) : _codecExecutor = codecExecutor ?? const IsolateMatrixRustCodecExecutor(),
       _syncRetryDelay = syncRetryDelay ?? Future<void>.delayed;

  final MatrixRustBridge bridge;
  final Uri homeserver;
  final MatrixSdkStoreSecretResolver resolveStoreSecret;
  final MatrixRustCodecExecutor _codecExecutor;
  final MatrixRustSyncDelay _syncRetryDelay;
  final StructuredLogger? logger;
  final CrashReporter? crashReporter;
  final StreamController<MatrixSyncBatch> _syncBatches =
      StreamController<MatrixSyncBatch>.broadcast(sync: true);

  MatrixRustClient? _client;
  Future<void> _transition = Future<void>.value();
  Future<void>? _syncLoop;
  Completer<void>? _retryWakeup;
  bool _syncRequested = false;

  @override
  Set<MatrixSdkCapability> get capabilities => const <MatrixSdkCapability>{
    MatrixSdkCapability.auditedEncryption,
    MatrixSdkCapability.encryptedPersistentStore,
    MatrixSdkCapability.incrementalSync,
    MatrixSdkCapability.backPagination,
  };

  @override
  Stream<MatrixSyncBatch> get syncBatches => _syncBatches.stream;

  @override
  Future<void> open(MatrixSdkStoreConfiguration store) {
    return _enqueue(() async {
      if (_client != null) return;
      final storeSecret = await resolveStoreSecret(store.encryptionKeyId);
      if (storeSecret.isEmpty) {
        throw StateError(
          'Matrix SDK store secret resolver returned an empty secret',
        );
      }
      if (storeSecret.contains('\u0000')) {
        throw ArgumentError.value(
          '<redacted>',
          'storeSecret',
          'must not contain NUL bytes',
        );
      }
      _client = await bridge.openEncryptedClient(
        homeserver: homeserver,
        storePath: store.storePath,
        storePassphrase: storeSecret,
      );
    });
  }

  @override
  Future<void> startSync(MatrixSdkSyncConfiguration configuration) {
    return _enqueue(() async {
      if (configuration.initialRoomListLimit <= 0 ||
          configuration.initialTimelineEventLimit <= 0 ||
          configuration.timelineEventLimit <= 0 ||
          configuration.initialTimelineEventLimit >
              configuration.timelineEventLimit ||
          configuration.resumeFromCursor?.isEmpty == true ||
          configuration.resumeFromCursor?.contains('\u0000') == true) {
        throw ArgumentError.value(
          configuration,
          'configuration',
          'contains invalid Matrix sync limits or resume cursor',
        );
      }
      if (_syncLoop != null) return;
      final client = _requireClient();
      _syncRequested = true;
      late final Future<void> loop;
      loop = _runSyncLoop(client, configuration).whenComplete(() {
        if (identical(_syncLoop, loop)) {
          _syncLoop = null;
        }
      });
      _syncLoop = loop;
      unawaited(loop);
    });
  }

  @override
  Future<void> stopSync() {
    return _enqueue(_stopSync);
  }

  @override
  Future<MatrixPaginationPage> paginateBackwards(String roomId) {
    return _enqueue<MatrixPaginationPage>(() async {
      final trace = logger?.trace(
        DiagnosticFlow.timeline,
        DiagnosticOperation.timelineUpdate,
      );
      trace?.log(LogLevel.info, DiagnosticEvent.started);
      try {
        final normalizedRoomId = roomId.trim();
        if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
          throw ArgumentError.value(
            roomId,
            'roomId',
            'must not be empty or contain NUL bytes',
          );
        }
        final payload = await _requireClient().paginateBackwards(
          roomId: normalizedRoomId,
        );
        final decoded = await _codecExecutor.decodePagination(payload);
        if (decoded.roomId != normalizedRoomId) {
          throw StateError('Matrix Rust SDK pagination room mismatch');
        }
        trace?.log(
          LogLevel.info,
          DiagnosticEvent.completed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.itemCount: decoded.events.length,
          },
        );
        return MatrixPaginationPage(
          roomId: decoded.roomId,
          events: decoded.events,
          reachedStart: decoded.reachedStart,
        );
      } catch (error, stackTrace) {
        trace?.log(LogLevel.error, DiagnosticEvent.failed);
        _reportFailure(
          error,
          stackTrace,
          trace,
          flow: DiagnosticFlow.timeline,
          operation: DiagnosticOperation.timelineUpdate,
          state: CrashState.active,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  @override
  Future<void> close() {
    return _enqueue(() async {
      await _stopSync();
      final client = _client;
      _client = null;
      await client?.close();
    });
  }

  Future<void> _runSyncLoop(
    MatrixRustClient client,
    MatrixSdkSyncConfiguration configuration,
  ) async {
    var firstRequest = true;
    var failureAttempt = 0;
    var syncToken = configuration.resumeFromCursor;
    final isColdStart = syncToken == null;
    while (_syncRequested && identical(_client, client)) {
      final trace = logger?.trace(
        DiagnosticFlow.sync,
        DiagnosticOperation.syncCycle,
      );
      trace?.log(LogLevel.info, DiagnosticEvent.started);
      try {
        final payload = await client.syncOnce(
          timeout: firstRequest ? Duration.zero : _matrixRustSyncPollTimeout,
          timelineEventLimit: firstRequest && isColdStart
              ? configuration.initialTimelineEventLimit
              : configuration.timelineEventLimit,
          since: syncToken,
        );
        if (!_syncRequested || !identical(_client, client)) return;
        final decoded = await _codecExecutor.decodeSync(payload);
        trace?.log(
          LogLevel.info,
          DiagnosticEvent.completed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.itemCount: decoded.batch.rooms.length,
          },
        );
        final fullyPublished = await _publishSyncBatch(
          decoded.batch,
          roomChunkSize: firstRequest && isColdStart
              ? configuration.initialRoomListLimit
              : null,
        );
        if (!fullyPublished) return;
        syncToken = decoded.batch.cursor;
        firstRequest = false;
        failureAttempt = 0;
      } catch (error, stackTrace) {
        if (!_syncRequested || !identical(_client, client)) return;
        failureAttempt += 1;
        final isPermanentPayloadFailure = error is FormatException;
        trace?.log(
          LogLevel.error,
          DiagnosticEvent.failed,
          metrics: <DiagnosticMetric, num>{
            DiagnosticMetric.attempt: failureAttempt,
          },
        );
        _reportFailure(
          error,
          stackTrace,
          trace,
          flow: DiagnosticFlow.sync,
          operation: DiagnosticOperation.syncCycle,
          state: isPermanentPayloadFailure
              ? CrashState.active
              : CrashState.retrying,
        );
        _syncBatches.addError(
          isPermanentPayloadFailure
              ? MatrixNonRetryableSyncException(error)
              : error,
          stackTrace,
        );
        if (isPermanentPayloadFailure) {
          _syncRequested = false;
          return;
        }
        await _waitForRetry(_matrixRustRetryDelayForAttempt(failureAttempt));
      }
    }
  }

  Future<bool> _publishSyncBatch(
    MatrixSyncBatch syncBatch, {
    required int? roomChunkSize,
  }) async {
    if (roomChunkSize == null || syncBatch.rooms.length <= roomChunkSize) {
      _syncBatches.add(syncBatch);
      return true;
    }

    for (
      var start = 0;
      start < syncBatch.rooms.length;
      start += roomChunkSize
    ) {
      if (!_syncRequested) return false;
      final end = start + roomChunkSize < syncBatch.rooms.length
          ? start + roomChunkSize
          : syncBatch.rooms.length;
      final isFinalChunk = end == syncBatch.rooms.length;
      _syncBatches.add(
        MatrixSyncBatch(
          cursor: syncBatch.cursor,
          rooms: List<MatrixRoomDelta>.unmodifiable(
            syncBatch.rooms.sublist(start, end),
          ),
          commitCursor: isFinalChunk,
        ),
      );
      if (!isFinalChunk) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return true;
  }

  void _reportFailure(
    Object error,
    StackTrace stackTrace,
    TraceLogger? trace, {
    required DiagnosticFlow flow,
    required DiagnosticOperation operation,
    required CrashState state,
  }) {
    final reporter = crashReporter;
    if (reporter == null || trace == null) return;
    try {
      final report = reporter.report(
        error,
        stackTrace: stackTrace,
        context: CrashDiagnosticContext(
          flow: flow,
          traceId: trace.traceId,
          operation: operation,
          component: CrashComponent.matrixSdk,
          state: state,
        ),
      );
      unawaited(report.catchError((Object _, StackTrace _) {}));
    } catch (_) {}
  }

  Future<void> _waitForRetry(Duration duration) async {
    final wakeup = Completer<void>();
    _retryWakeup = wakeup;
    try {
      if (!_syncRequested) return;
      await Future.any<void>(<Future<void>>[
        _syncRetryDelay(duration),
        wakeup.future,
      ]);
    } finally {
      if (identical(_retryWakeup, wakeup)) {
        _retryWakeup = null;
      }
    }
  }

  Future<void> _stopSync() async {
    _syncRequested = false;
    final wakeup = _retryWakeup;
    if (wakeup != null && !wakeup.isCompleted) {
      wakeup.complete();
    }
    final loop = _syncLoop;
    if (loop != null) {
      await loop;
      if (identical(_syncLoop, loop)) {
        _syncLoop = null;
      }
    }
  }

  MatrixRustClient _requireClient() {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('Matrix Rust SDK client is not open');
    }
    return client;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _transition.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace _) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    _transition = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }
}
