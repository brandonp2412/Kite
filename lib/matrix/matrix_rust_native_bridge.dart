import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_rust_sync_codec.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';

const int kiteMatrixNativeAbiVersion = 29;

const Duration _matrixRustSyncPollTimeout = Duration(seconds: 5);
const int _matrixRustMaxRetryDelaySeconds = 30;

enum _MatrixRustSyncFailureCode {
  unknownPosition,
  unknownToken,
  sessionPersistence,
  refreshToken,
  authenticationRequired,
  network,
  api,
  stateStore,
  eventCacheStore,
  other,
}

final class _MatrixRustSyncFailure implements Exception {
  const _MatrixRustSyncFailure(this.code);

  final _MatrixRustSyncFailureCode code;

  bool get isPermanent =>
      code == _MatrixRustSyncFailureCode.unknownPosition ||
      code == _MatrixRustSyncFailureCode.unknownToken ||
      code == _MatrixRustSyncFailureCode.sessionPersistence ||
      code == _MatrixRustSyncFailureCode.refreshToken ||
      code == _MatrixRustSyncFailureCode.authenticationRequired ||
      code == _MatrixRustSyncFailureCode.stateStore ||
      code == _MatrixRustSyncFailureCode.eventCacheStore;

  bool get isSessionExpired =>
      code == _MatrixRustSyncFailureCode.unknownToken ||
      code == _MatrixRustSyncFailureCode.refreshToken ||
      code == _MatrixRustSyncFailureCode.authenticationRequired;

  @override
  String toString() => 'Matrix Rust SDK sync failed (${code.name})';
}

_MatrixRustSyncFailure? _decodeMatrixRustSyncFailure(String payload) {
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final error = decoded['error'];
  if (error is! Map) return null;
  final code = error['code'];
  if (code is! String) return null;
  return _MatrixRustSyncFailure(switch (code) {
    'unknown_pos' => _MatrixRustSyncFailureCode.unknownPosition,
    'unknown_token' => _MatrixRustSyncFailureCode.unknownToken,
    'session_persist_failed' => _MatrixRustSyncFailureCode.sessionPersistence,
    'refresh_token_failed' => _MatrixRustSyncFailureCode.refreshToken,
    'authentication_required' =>
      _MatrixRustSyncFailureCode.authenticationRequired,
    'network_failed' => _MatrixRustSyncFailureCode.network,
    'api_failed' => _MatrixRustSyncFailureCode.api,
    'state_store_failed' => _MatrixRustSyncFailureCode.stateStore,
    'event_cache_store_failed' => _MatrixRustSyncFailureCode.eventCacheStore,
    _ => _MatrixRustSyncFailureCode.other,
  });
}

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
typedef _ClientCreateRoomNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _ClientCreateRoomDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
);
typedef _ClientSetRoomFavouriteNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Uint8,
);
typedef _ClientSetRoomFavouriteDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  int,
);
typedef _ClientRespondInviteNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Uint8,
);
typedef _ClientRespondInviteDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  int,
);
typedef _ClientMarkRoomReadNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientMarkRoomReadDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientInviteRoomMemberNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientInviteRoomMemberDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRoomMemberPermissionsNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRoomMemberPermissionsDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientModerateRoomMemberNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Int64,
  Pointer<Char>,
);
typedef _ClientModerateRoomMemberDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  int,
  Pointer<Char>,
);
typedef _ClientManageRoomNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientManageRoomDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientReportContentNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientReportContentDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRedactEventNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRedactEventDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRoomSettingsNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRoomSettingsDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientProfileNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientProfileDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRecoveryNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientRecoveryDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientUploadMediaNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Uint8>,
  Uint64,
);
typedef _ClientUploadMediaDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Uint8>,
  int,
);
typedef _ClientPrefetchMediaNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Uint64,
  Uint64,
);
typedef _ClientPrefetchMediaDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  int,
  int,
);
typedef _ClientDownloadMediaNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Uint64,
  Uint64,
);
typedef _ClientDownloadMediaDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  int,
  int,
);
typedef _DiscoverAuthenticationNative = Pointer<Char> Function(Pointer<Char>);
typedef _DiscoverAuthenticationDart = Pointer<Char> Function(Pointer<Char>);
typedef _ClientLoginPasswordNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientLoginPasswordDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSendTextNative = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSendTextDart = Pointer<Char> Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef _ClientSessionOperationNative = Pointer<Char> Function(Pointer<Void>);
typedef _ClientSessionOperationDart = Pointer<Char> Function(Pointer<Void>);
typedef _StringFreeNative = Void Function(Pointer<Char> value);
typedef _StringFreeDart = void Function(Pointer<Char> value);
typedef _ClientFreeNative = Void Function(Pointer<Void> client);
typedef _ClientFreeDart = void Function(Pointer<Void> client);

typedef MatrixSdkStoreSecretResolver = Future<String> Function(String keyId);
typedef MatrixRustSyncDelay = Future<void> Function(Duration duration);

final class MatrixRustLoginResult {
  const MatrixRustLoginResult({required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;
}

final class MatrixRustSendResult {
  const MatrixRustSendResult({required this.eventId});

  final String eventId;
}

final class MatrixRustCreatedRoom {
  const MatrixRustCreatedRoom({required this.roomId, required this.isDirect});

  final String roomId;
  final bool isDirect;
}

final class MatrixRustRoomMember {
  const MatrixRustRoomMember({
    required this.userId,
    required this.displayName,
    required this.powerLevel,
  });

  final String userId;
  final String displayName;
  final int powerLevel;
}

final class MatrixRustRoomMemberPermissions {
  const MatrixRustRoomMemberPermissions({
    required this.actorPowerLevel,
    required this.canInvite,
    required this.canChangePowerLevel,
    required this.canKick,
    required this.canBan,
    required this.canUnban,
  });

  final int actorPowerLevel;
  final bool canInvite;
  final bool canChangePowerLevel;
  final bool canKick;
  final bool canBan;
  final bool canUnban;
}

final class MatrixRustNativeException implements Exception {
  const MatrixRustNativeException({
    required this.code,
    required this.publicMessage,
  });

  final String code;
  final String publicMessage;

  @override
  String toString() =>
      'MatrixRustNativeException(code: $code, detail: <redacted>)';
}

final class MatrixRustAuthenticationDiscovery {
  const MatrixRustAuthenticationDiscovery({
    required this.homeserver,
    required this.passwordAvailable,
  });

  final Uri homeserver;
  final bool passwordAvailable;
}

final class MatrixRustSessionDescriptor {
  const MatrixRustSessionDescriptor({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  final String userId;
  final String deviceId;
  final Uri homeserver;
}

Object? _decodeNativeEnvelope(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned an invalid response.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned an invalid response.',
    );
  }
  if (decoded['ok'] == true) return decoded['value'];
  final error = decoded['error'];
  if (error is Map<String, dynamic>) {
    final code = error['code'];
    final message = error['message'];
    if (code is String && message is String) {
      throw MatrixRustNativeException(code: code, publicMessage: message);
    }
  }
  throw const MatrixRustNativeException(
    code: 'native_operation_failed',
    publicMessage: 'The Matrix native operation failed.',
  );
}

MatrixRustSessionDescriptor _decodeSessionDescriptor(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned invalid session data.',
    );
  }
  final userId = value['userId'];
  final deviceId = value['deviceId'];
  final homeserver = value['homeserver'];
  final parsedHomeserver = homeserver is String
      ? Uri.tryParse(homeserver)
      : null;
  if (userId is! String ||
      userId.isEmpty ||
      deviceId is! String ||
      deviceId.isEmpty ||
      parsedHomeserver == null ||
      !parsedHomeserver.hasScheme) {
    throw const MatrixRustNativeException(
      code: 'invalid_native_response',
      publicMessage: 'The Matrix native bridge returned invalid session data.',
    );
  }
  return MatrixRustSessionDescriptor(
    userId: userId,
    deviceId: deviceId,
    homeserver: parsedHomeserver,
  );
}

String _readNativeString(
  Pointer<Char> value,
  _StringFreeDart freeString,
  String operation,
) {
  if (value == nullptr) {
    throw StateError('Matrix Rust SDK $operation returned no result');
  }
  try {
    return value.cast<Utf8>().toDartString();
  } finally {
    freeString(value);
  }
}

final class _MatrixNativeDiscoverAuthenticationOperation {
  const _MatrixNativeDiscoverAuthenticationOperation({
    required this.libraryPath,
    required this.homeserver,
  });

  final String libraryPath;
  final String homeserver;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final discover = library
        .lookupFunction<
          _DiscoverAuthenticationNative,
          _DiscoverAuthenticationDart
        >('kite_matrix_discover_authentication');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final homeserverUtf8 = homeserver.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        discover(homeserverUtf8.cast<Char>()),
        freeString,
        'authentication discovery',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(homeserverUtf8);
    }
  }
}

final class _MatrixNativeLoginPasswordOperation {
  const _MatrixNativeLoginPasswordOperation({
    required this.libraryPath,
    required this.address,
    required this.username,
    required this.password,
  });

  final String libraryPath;
  final int address;
  final String username;
  final String password;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final login = library
        .lookupFunction<_ClientLoginPasswordNative, _ClientLoginPasswordDart>(
          'kite_matrix_client_login_password',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final usernameUtf8 = username.toNativeUtf8(allocator: calloc);
    final passwordUtf8 = password.toNativeUtf8(allocator: calloc);
    final passwordBytes = passwordUtf8.cast<Uint8>().asTypedList(
      passwordUtf8.length + 1,
    );
    try {
      final value = login(
        Pointer<Void>.fromAddress(address),
        usernameUtf8.cast<Char>(),
        passwordUtf8.cast<Char>(),
      );
      final payload = _readNativeString(value, freeString, 'password login');
      return _decodeNativeEnvelope(payload);
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      calloc.free(passwordUtf8);
      calloc.free(usernameUtf8);
    }
  }
}

final class _MatrixNativeSendTextOperation {
  const _MatrixNativeSendTextOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.transactionId,
    required this.body,
    required this.replyToEventId,
    required this.replacementEventId,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String transactionId;
  final String body;
  final String? replyToEventId;
  final String? replacementEventId;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final send = library
        .lookupFunction<_ClientSendTextNative, _ClientSendTextDart>(
          'kite_matrix_client_send_text',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final transactionIdUtf8 = transactionId.toNativeUtf8(allocator: calloc);
    final bodyUtf8 = body.toNativeUtf8(allocator: calloc);
    final replyToEventIdUtf8 = replyToEventId?.toNativeUtf8(allocator: calloc);
    final replacementEventIdUtf8 = replacementEventId?.toNativeUtf8(
      allocator: calloc,
    );
    try {
      final value = send(
        Pointer<Void>.fromAddress(address),
        roomIdUtf8.cast<Char>(),
        transactionIdUtf8.cast<Char>(),
        bodyUtf8.cast<Char>(),
        replyToEventIdUtf8 == null
            ? Pointer<Char>.fromAddress(0)
            : replyToEventIdUtf8.cast<Char>(),
        replacementEventIdUtf8 == null
            ? Pointer<Char>.fromAddress(0)
            : replacementEventIdUtf8.cast<Char>(),
      );
      final payload = _readNativeString(value, freeString, 'text send');
      return _decodeNativeEnvelope(payload);
    } finally {
      if (replacementEventIdUtf8 != null) calloc.free(replacementEventIdUtf8);
      if (replyToEventIdUtf8 != null) calloc.free(replyToEventIdUtf8);
      calloc.free(bodyUtf8);
      calloc.free(transactionIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeSessionOperation {
  const _MatrixNativeSessionOperation({
    required this.libraryPath,
    required this.address,
    required this.symbol,
    required this.operation,
  });

  final String libraryPath;
  final int address;
  final String symbol;
  final String operation;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final sessionOperation = library
        .lookupFunction<
          _ClientSessionOperationNative,
          _ClientSessionOperationDart
        >(symbol);
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final payload = _readNativeString(
      sessionOperation(Pointer<Void>.fromAddress(address)),
      freeString,
      operation,
    );
    return _decodeNativeEnvelope(payload);
  }
}

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

final class _MatrixNativeCreateRoomOperation {
  const _MatrixNativeCreateRoomOperation({
    required this.libraryPath,
    required this.address,
    required this.payload,
  });

  final String libraryPath;
  final int address;
  final String payload;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final createRoom = library
        .lookupFunction<_ClientCreateRoomNative, _ClientCreateRoomDart>(
          'kite_matrix_client_create_room',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final payloadUtf8 = payload.toNativeUtf8(allocator: calloc);
    try {
      final response = _readNativeString(
        createRoom(
          Pointer<Void>.fromAddress(address),
          payloadUtf8.cast<Char>(),
        ),
        freeString,
        'room creation',
      );
      return _decodeNativeEnvelope(response);
    } finally {
      calloc.free(payloadUtf8);
    }
  }
}

final class _MatrixNativeSetRoomFavouriteOperation {
  const _MatrixNativeSetRoomFavouriteOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.isFavourite,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final bool isFavourite;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final setFavourite = library
        .lookupFunction<
          _ClientSetRoomFavouriteNative,
          _ClientSetRoomFavouriteDart
        >('kite_matrix_client_set_room_favourite');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        setFavourite(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          isFavourite ? 1 : 0,
        ),
        freeString,
        'room favourite update',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeRespondInviteOperation {
  const _MatrixNativeRespondInviteOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.accept,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final bool accept;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final respond = library
        .lookupFunction<_ClientRespondInviteNative, _ClientRespondInviteDart>(
          'kite_matrix_client_respond_to_invite',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        respond(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          accept ? 1 : 0,
        ),
        freeString,
        accept ? 'room invite acceptance' : 'room invite decline',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeMarkRoomReadOperation {
  const _MatrixNativeMarkRoomReadOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.eventId,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String eventId;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final markRead = library
        .lookupFunction<_ClientMarkRoomReadNative, _ClientMarkRoomReadDart>(
          'kite_matrix_client_mark_room_read',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final eventIdUtf8 = eventId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        markRead(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          eventIdUtf8.cast<Char>(),
        ),
        freeString,
        'room read receipt',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(eventIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeInviteRoomMemberOperation {
  const _MatrixNativeInviteRoomMemberOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.userId,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String userId;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final inviteMember = library
        .lookupFunction<
          _ClientInviteRoomMemberNative,
          _ClientInviteRoomMemberDart
        >('kite_matrix_client_invite_room_member');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final userIdUtf8 = userId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        inviteMember(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          userIdUtf8.cast<Char>(),
        ),
        freeString,
        'room member invitation',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(userIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeRoomMemberPermissionsOperation {
  const _MatrixNativeRoomMemberPermissionsOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.actorUserId,
    required this.targetUserId,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String actorUserId;
  final String targetUserId;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final permissions = library
        .lookupFunction<
          _ClientRoomMemberPermissionsNative,
          _ClientRoomMemberPermissionsDart
        >('kite_matrix_client_room_member_permissions');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final actorUserIdUtf8 = actorUserId.toNativeUtf8(allocator: calloc);
    final targetUserIdUtf8 = targetUserId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        permissions(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          actorUserIdUtf8.cast<Char>(),
          targetUserIdUtf8.cast<Char>(),
        ),
        freeString,
        'room member permissions',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid room member permissions.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      calloc.free(targetUserIdUtf8);
      calloc.free(actorUserIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeModerateRoomMemberOperation {
  const _MatrixNativeModerateRoomMemberOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.userId,
    required this.action,
    required this.powerLevel,
    required this.reason,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String userId;
  final String action;
  final int powerLevel;
  final String reason;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final moderate = library
        .lookupFunction<
          _ClientModerateRoomMemberNative,
          _ClientModerateRoomMemberDart
        >('kite_matrix_client_moderate_room_member');
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final userIdUtf8 = userId.toNativeUtf8(allocator: calloc);
    final actionUtf8 = action.toNativeUtf8(allocator: calloc);
    final reasonUtf8 = reason.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        moderate(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          userIdUtf8.cast<Char>(),
          actionUtf8.cast<Char>(),
          powerLevel,
          reasonUtf8.cast<Char>(),
        ),
        freeString,
        'room member moderation',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(reasonUtf8);
      calloc.free(actionUtf8);
      calloc.free(userIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeManageRoomOperation {
  const _MatrixNativeManageRoomOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.action,
    required this.userId,
    required this.reason,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String action;
  final String userId;
  final String reason;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final manage = library
        .lookupFunction<_ClientManageRoomNative, _ClientManageRoomDart>(
          'kite_matrix_client_manage_room',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final actionUtf8 = action.toNativeUtf8(allocator: calloc);
    final userIdUtf8 = userId.toNativeUtf8(allocator: calloc);
    final reasonUtf8 = reason.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        manage(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          actionUtf8.cast<Char>(),
          userIdUtf8.cast<Char>(),
          reasonUtf8.cast<Char>(),
        ),
        freeString,
        'room management',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(reasonUtf8);
      calloc.free(userIdUtf8);
      calloc.free(actionUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeReportContentOperation {
  const _MatrixNativeReportContentOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.eventId,
    required this.reason,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String eventId;
  final String reason;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final report = library
        .lookupFunction<_ClientReportContentNative, _ClientReportContentDart>(
          'kite_matrix_client_report_content',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final eventIdUtf8 = eventId.toNativeUtf8(allocator: calloc);
    final reasonUtf8 = reason.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        report(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          eventIdUtf8.cast<Char>(),
          reasonUtf8.cast<Char>(),
        ),
        freeString,
        'event reporting',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(reasonUtf8);
      calloc.free(eventIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeRedactEventOperation {
  const _MatrixNativeRedactEventOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.eventId,
    required this.transactionId,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String eventId;
  final String transactionId;

  Object? call() {
    final library = DynamicLibrary.open(libraryPath);
    final redact = library
        .lookupFunction<_ClientRedactEventNative, _ClientRedactEventDart>(
          'kite_matrix_client_redact_event',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final eventIdUtf8 = eventId.toNativeUtf8(allocator: calloc);
    final transactionIdUtf8 = transactionId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        redact(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          eventIdUtf8.cast<Char>(),
          transactionIdUtf8.cast<Char>(),
        ),
        freeString,
        'event redaction',
      );
      return _decodeNativeEnvelope(payload);
    } finally {
      calloc.free(transactionIdUtf8);
      calloc.free(eventIdUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeProfileOperation {
  const _MatrixNativeProfileOperation({
    required this.libraryPath,
    required this.address,
    required this.userId,
    required this.action,
    required this.value,
  });

  final String libraryPath;
  final int address;
  final String? userId;
  final String action;
  final String? value;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final profile = library
        .lookupFunction<_ClientProfileNative, _ClientProfileDart>(
          'kite_matrix_client_profile',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final userIdUtf8 = userId?.toNativeUtf8(allocator: calloc);
    final actionUtf8 = action.toNativeUtf8(allocator: calloc);
    final valueUtf8 = value?.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        profile(
          Pointer<Void>.fromAddress(address),
          userIdUtf8 == null
              ? Pointer<Char>.fromAddress(0)
              : userIdUtf8.cast<Char>(),
          actionUtf8.cast<Char>(),
          valueUtf8 == null
              ? Pointer<Char>.fromAddress(0)
              : valueUtf8.cast<Char>(),
        ),
        freeString,
        'profile',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid profile data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      if (valueUtf8 != null) calloc.free(valueUtf8);
      calloc.free(actionUtf8);
      if (userIdUtf8 != null) calloc.free(userIdUtf8);
    }
  }
}

final class _MatrixNativeRecoveryOperation {
  const _MatrixNativeRecoveryOperation({
    required this.libraryPath,
    required this.address,
    required this.action,
    required this.secret,
  });

  final String libraryPath;
  final int address;
  final String action;
  final String? secret;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final recovery = library
        .lookupFunction<_ClientRecoveryNative, _ClientRecoveryDart>(
          'kite_matrix_client_recovery',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final actionUtf8 = action.toNativeUtf8(allocator: calloc);
    final secretUtf8 = secret?.toNativeUtf8(allocator: calloc);
    final secretByteLength = secret == null
        ? 0
        : utf8.encode(secret!).length + 1;
    try {
      final payload = _readNativeString(
        recovery(
          Pointer<Void>.fromAddress(address),
          actionUtf8.cast<Char>(),
          secretUtf8 == null
              ? Pointer<Char>.fromAddress(0)
              : secretUtf8.cast<Char>(),
        ),
        freeString,
        'encryption recovery',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid recovery data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      if (secretUtf8 != null) {
        final bytes = secretUtf8.cast<Uint8>().asTypedList(secretByteLength);
        bytes.fillRange(0, bytes.length, 0);
        calloc.free(secretUtf8);
      }
      calloc.free(actionUtf8);
    }
  }
}

final class _MatrixNativeRoomKeyImportOperation {
  const _MatrixNativeRoomKeyImportOperation({
    required this.libraryPath,
    required this.address,
    required this.path,
    required this.passphrase,
  });

  final String libraryPath;
  final int address;
  final String path;
  final String passphrase;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final importRoomKeys = library
        .lookupFunction<_ClientRecoveryNative, _ClientRecoveryDart>(
          'kite_matrix_client_import_room_keys',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final pathUtf8 = path.toNativeUtf8(allocator: calloc);
    final passphraseUtf8 = passphrase.toNativeUtf8(allocator: calloc);
    final passphraseByteLength = utf8.encode(passphrase).length + 1;
    try {
      final payload = _readNativeString(
        importRoomKeys(
          Pointer<Void>.fromAddress(address),
          pathUtf8.cast<Char>(),
          passphraseUtf8.cast<Char>(),
        ),
        freeString,
        'room-key import',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room-key import data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      final secretBytes = passphraseUtf8.cast<Uint8>().asTypedList(
        passphraseByteLength,
      );
      secretBytes.fillRange(0, secretBytes.length, 0);
      calloc.free(passphraseUtf8);
      calloc.free(pathUtf8);
    }
  }
}

final class _MatrixNativeUploadMediaOperation {
  const _MatrixNativeUploadMediaOperation({
    required this.libraryPath,
    required this.address,
    required this.mimeType,
    required this.bytes,
  });

  final String libraryPath;
  final int address;
  final String mimeType;
  final Uint8List bytes;

  String call() {
    final library = DynamicLibrary.open(libraryPath);
    final upload = library
        .lookupFunction<_ClientUploadMediaNative, _ClientUploadMediaDart>(
          'kite_matrix_client_upload_media',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final mimeTypeUtf8 = mimeType.toNativeUtf8(allocator: calloc);
    final data = calloc<Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final payload = _readNativeString(
        upload(
          Pointer<Void>.fromAddress(address),
          mimeTypeUtf8.cast<Char>(),
          data,
          bytes.length,
        ),
        freeString,
        'media upload',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      final contentUri = decoded['contentUri'];
      if (contentUri is! String ||
          contentUri.isEmpty ||
          !contentUri.startsWith('mxc://')) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      return contentUri;
    } finally {
      data.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(data);
      calloc.free(mimeTypeUtf8);
    }
  }
}

final class _MatrixNativeDownloadMediaOperation {
  const _MatrixNativeDownloadMediaOperation({
    required this.libraryPath,
    required this.address,
    required this.contentUri,
    required this.width,
    required this.height,
  });

  final String libraryPath;
  final int address;
  final String contentUri;
  final int width;
  final int height;

  Uint8List call() {
    final library = DynamicLibrary.open(libraryPath);
    final download = library
        .lookupFunction<_ClientDownloadMediaNative, _ClientDownloadMediaDart>(
          'kite_matrix_client_download_media',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final contentUriUtf8 = contentUri.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        download(
          Pointer<Void>.fromAddress(address),
          contentUriUtf8.cast<Char>(),
          width,
          height,
        ),
        freeString,
        'media download',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      final encoded = decoded['data'];
      if (encoded is! String || encoded.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      Uint8List bytes;
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      if (bytes.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media data.',
        );
      }
      return bytes;
    } finally {
      calloc.free(contentUriUtf8);
    }
  }
}

final class _MatrixNativePrefetchMediaOperation {
  const _MatrixNativePrefetchMediaOperation({
    required this.libraryPath,
    required this.address,
    required this.contentUrisJson,
    required this.width,
    required this.height,
  });

  final String libraryPath;
  final int address;
  final String contentUrisJson;
  final int width;
  final int height;

  Map<String, Uint8List> call() {
    final library = DynamicLibrary.open(libraryPath);
    final prefetch = library
        .lookupFunction<_ClientPrefetchMediaNative, _ClientPrefetchMediaDart>(
          'kite_matrix_client_prefetch_media',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final contentUrisUtf8 = contentUrisJson.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        prefetch(
          Pointer<Void>.fromAddress(address),
          contentUrisUtf8.cast<Char>(),
          width,
          height,
        ),
        freeString,
        'media prefetch',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media prefetch data.',
        );
      }
      final requested = decoded['requested'];
      final completed = decoded['completed'];
      final failed = decoded['failed'];
      final items = decoded['items'];
      if (requested is! int ||
          completed is! int ||
          failed is! int ||
          items is! List ||
          requested < 0 ||
          completed < 0 ||
          failed < 0 ||
          completed + failed != requested ||
          items.length != completed) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid media prefetch data.',
        );
      }
      final result = <String, Uint8List>{};
      for (final item in items) {
        if (item is! Map<String, dynamic>) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage: 'The Matrix native bridge returned invalid media prefetch data.',
          );
        }
        final contentUri = item['contentUri'];
        final encoded = item['data'];
        if (contentUri is! String ||
            !contentUri.startsWith('mxc://') ||
            encoded is! String ||
            encoded.isEmpty) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage: 'The Matrix native bridge returned invalid media prefetch data.',
          );
        }
        Uint8List bytes;
        try {
          bytes = base64Decode(encoded);
        } on FormatException {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage: 'The Matrix native bridge returned invalid media prefetch data.',
          );
        }
        if (bytes.isEmpty || result.containsKey(contentUri)) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage: 'The Matrix native bridge returned invalid media prefetch data.',
          );
        }
        result[contentUri] = bytes;
      }
      return Map<String, Uint8List>.unmodifiable(result);
    } finally {
      calloc.free(contentUrisUtf8);
    }
  }
}

final class _MatrixNativeRoomSettingsOperation {
  const _MatrixNativeRoomSettingsOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
    required this.action,
    required this.value,
  });

  final String libraryPath;
  final int address;
  final String roomId;
  final String action;
  final String? value;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final roomSettings = library
        .lookupFunction<_ClientRoomSettingsNative, _ClientRoomSettingsDart>(
          'kite_matrix_client_room_settings',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    final actionUtf8 = action.toNativeUtf8(allocator: calloc);
    final valueUtf8 = value?.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        roomSettings(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
          actionUtf8.cast<Char>(),
          valueUtf8 == null
              ? Pointer<Char>.fromAddress(0)
              : valueUtf8.cast<Char>(),
        ),
        freeString,
        'room settings',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room settings data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      if (valueUtf8 != null) calloc.free(valueUtf8);
      calloc.free(actionUtf8);
      calloc.free(roomIdUtf8);
    }
  }
}

final class _MatrixNativeRoomMembersOperation {
  const _MatrixNativeRoomMembersOperation({
    required this.libraryPath,
    required this.address,
    required this.roomId,
  });

  final String libraryPath;
  final int address;
  final String roomId;

  Map<String, Object?> call() {
    final library = DynamicLibrary.open(libraryPath);
    final roomMembers = library
        .lookupFunction<_ClientPaginateNative, _ClientPaginateDart>(
          'kite_matrix_client_room_members',
        );
    final freeString = library
        .lookupFunction<_StringFreeNative, _StringFreeDart>(
          'kite_matrix_string_free',
        );
    final roomIdUtf8 = roomId.toNativeUtf8(allocator: calloc);
    try {
      final payload = _readNativeString(
        roomMembers(
          Pointer<Void>.fromAddress(address),
          roomIdUtf8.cast<Char>(),
        ),
        freeString,
        'room member lookup',
      );
      final decoded = _decodeNativeEnvelope(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room member data.',
        );
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      calloc.free(roomIdUtf8);
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
        final payload = value.cast<Utf8>().toDartString();
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error'];
          if (error is String) {
            throw StateError('Matrix Rust SDK back-pagination failed: $error');
          }
        }
        return payload;
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

abstract interface class MatrixRustAuthenticationBridge {
  Future<MatrixRustAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  );
}

abstract interface class MatrixRustSessionClient {
  Future<MatrixRustSessionDescriptor?> restoreSession();

  Future<void> persistSession();
}

abstract interface class MatrixRustLogoutClient {
  Future<void> logout();
}

abstract interface class MatrixRustBridge {
  Future<MatrixRustClient> openEncryptedClient({
    required Uri homeserver,
    required String storePath,
    required String storePassphrase,
  });
}

abstract interface class MatrixRustRoomCreator {
  Future<MatrixRustCreatedRoom> createRoom(
    MatrixSdkRoomCreationRequest request,
  );
}

abstract interface class MatrixRustRoomMembersClient {
  Future<List<MatrixRustRoomMember>> roomMembers({required String roomId});
}

abstract interface class MatrixRustRoomMemberInviterClient {
  Future<void> inviteRoomMember({
    required String roomId,
    required String userId,
  });
}

abstract interface class MatrixRustRoomMemberModeratorClient {
  Future<MatrixRustRoomMemberPermissions> roomMemberPermissions({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
  });

  Future<void> moderateRoomMember({
    required String roomId,
    required String userId,
    required String action,
    int powerLevel = 0,
    String? reason,
  });
}

abstract interface class MatrixRustRoomLifecycleClient {
  Future<void> manageRoom({
    required String roomId,
    required String action,
    String? userId,
    String? reason,
  });
}

abstract interface class MatrixRustTimelineModerationClient {
  Future<void> reportContent({
    required String roomId,
    required String eventId,
    String? reason,
  });
}

abstract interface class MatrixRustTimelineRedactionClient {
  Future<void> redactEvent({
    required String roomId,
    required String eventId,
    required String transactionId,
  });
}

abstract interface class MatrixRustMediaPrefetchClient {
  Future<Map<String, Uint8List>> prefetchMedia({
    required List<String> contentUris,
    required int width,
    required int height,
  });
}

abstract interface class MatrixRustMediaClient {
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  });

  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  });
}

abstract interface class MatrixRustProfileClient {
  Future<Map<String, Object?>> profile({
    String? userId,
    required String action,
    String? value,
  });
}

abstract interface class MatrixRustEncryptionRecoveryClient {
  Future<Map<String, Object?>> encryptionRecoveryStatus();

  Future<Map<String, Object?>> createEncryptedBackup();

  Future<Map<String, Object?>> recoverEncryption(String secret);

  Future<Map<String, Object?>> recoverEncryptedHistory();

  Future<Map<String, Object?>> importRoomKeyBackup({
    required String path,
    required String passphrase,
  });
}

abstract interface class MatrixRustRoomSettingsClient {
  Future<Map<String, Object?>> roomSettings({
    required String roomId,
    required String action,
    String? value,
  });
}

abstract interface class MatrixRustRoomFavouriteClient {
  Future<void> setRoomFavourite({
    required String roomId,
    required bool isFavourite,
  });
}

abstract interface class MatrixRustRoomInviteClient {
  Future<void> respondToInvite({required String roomId, required bool accept});
}

abstract interface class MatrixRustRoomReadClient {
  Future<void> markRoomRead({required String roomId, required String eventId});
}

abstract interface class MatrixRustClient {
  bool get isClosed;

  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  });

  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  });

  Future<String> syncOnce({
    required Duration timeout,
    required int timelineEventLimit,
    String? since,
  });

  Future<String> paginateBackwards({required String roomId});

  Future<void> close();
}

final class MatrixRustNativeBridge
    implements MatrixRustBridge, MatrixRustAuthenticationBridge {
  const MatrixRustNativeBridge({required this.libraryPath});

  final String libraryPath;

  @override
  Future<MatrixRustAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    final homeserverText = homeserver.toString().trim();
    if (homeserverText.isEmpty || homeserverText.contains('\u0000')) {
      throw ArgumentError.value(
        homeserver,
        'homeserver',
        'must not be empty or contain NUL bytes',
      );
    }
    final value = await Isolate.run<Object?>(
      _MatrixNativeDiscoverAuthenticationOperation(
        libraryPath: libraryPath,
        homeserver: homeserverText,
      ).call,
    );
    if (value is! Map<String, dynamic>) {
      throw const MatrixRustNativeException(
        code: 'invalid_native_response',
        publicMessage:
            'The Matrix native bridge returned invalid discovery data.',
      );
    }
    final discoveredHomeserver = value['homeserver'];
    final passwordAvailable = value['password'];
    final parsedHomeserver = discoveredHomeserver is String
        ? Uri.tryParse(discoveredHomeserver)
        : null;
    if (parsedHomeserver == null ||
        !parsedHomeserver.hasScheme ||
        passwordAvailable is! bool) {
      throw const MatrixRustNativeException(
        code: 'invalid_native_response',
        publicMessage:
            'The Matrix native bridge returned invalid discovery data.',
      );
    }
    return MatrixRustAuthenticationDiscovery(
      homeserver: parsedHomeserver,
      passwordAvailable: passwordAvailable,
    );
  }

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

enum _MatrixOperationPriority { critical, interactive, normal, background }

final class _MatrixSerialOperationQueue {
  final Queue<Future<void> Function()> _critical =
      Queue<Future<void> Function()>();
  final Queue<Future<void> Function()> _interactive =
      Queue<Future<void> Function()>();
  final Queue<Future<void> Function()> _normal =
      Queue<Future<void> Function()>();
  final Queue<Future<void> Function()> _background =
      Queue<Future<void> Function()>();

  bool _draining = false;

  Future<T> enqueue<T>(
    Future<T> Function() operation, {
    _MatrixOperationPriority priority = _MatrixOperationPriority.normal,
  }) {
    final completer = Completer<T>();
    Future<void> task() async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    switch (priority) {
      case _MatrixOperationPriority.critical:
        _critical.add(task);
      case _MatrixOperationPriority.interactive:
        _interactive.add(task);
      case _MatrixOperationPriority.normal:
        _normal.add(task);
      case _MatrixOperationPriority.background:
        _background.add(task);
    }
    _scheduleDrain();
    return completer.future;
  }

  bool get _hasPending =>
      _critical.isNotEmpty ||
      _interactive.isNotEmpty ||
      _normal.isNotEmpty ||
      _background.isNotEmpty;

  Future<void> Function()? _takeNext() {
    if (_critical.isNotEmpty) return _critical.removeFirst();
    if (_interactive.isNotEmpty) return _interactive.removeFirst();
    if (_normal.isNotEmpty) return _normal.removeFirst();
    if (_background.isNotEmpty) return _background.removeFirst();
    return null;
  }

  void _scheduleDrain() {
    if (_draining) return;
    _draining = true;
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (true) {
        final task = _takeNext();
        if (task == null) return;
        await task();
      }
    } finally {
      _draining = false;
      if (_hasPending) _scheduleDrain();
    }
  }
}

final class MatrixRustNativeClient
    implements
        MatrixRustClient,
        MatrixRustSessionClient,
        MatrixRustLogoutClient,
        MatrixRustRoomCreator,
        MatrixRustRoomMembersClient,
        MatrixRustRoomMemberInviterClient,
        MatrixRustRoomMemberModeratorClient,
        MatrixRustRoomLifecycleClient,
        MatrixRustTimelineModerationClient,
        MatrixRustTimelineRedactionClient,
        MatrixRustRoomSettingsClient,
        MatrixRustMediaPrefetchClient,
        MatrixRustMediaClient,
        MatrixRustProfileClient,
        MatrixRustEncryptionRecoveryClient,
        MatrixRustRoomFavouriteClient,
        MatrixRustRoomInviteClient,
        MatrixRustRoomReadClient {
  MatrixRustNativeClient._(this.libraryPath, this._address);

  final String libraryPath;
  int _address;
  final _operations = _MatrixSerialOperationQueue();

  @override
  bool get isClosed => _address == 0;

  @override
  Future<MatrixRustLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || normalizedUsername.contains('\u0000')) {
      return Future<MatrixRustLoginResult>.error(
        ArgumentError.value(
          username,
          'username',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (password.isEmpty || password.contains('\u0000')) {
      return Future<MatrixRustLoginResult>.error(
        ArgumentError.value(
          '<redacted>',
          'password',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<MatrixRustLoginResult>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeLoginPasswordOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          username: normalizedUsername,
          password: password,
        ).call,
      );
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid login data.',
        );
      }
      final userId = decoded['userId'];
      final deviceId = decoded['deviceId'];
      if (userId is! String ||
          userId.isEmpty ||
          deviceId is! String ||
          deviceId.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid login data.',
        );
      }
      return MatrixRustLoginResult(userId: userId, deviceId: deviceId);
    });
  }

  @override
  Future<MatrixRustSendResult> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedTransactionId = transactionId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedTransactionId.isEmpty ||
        normalizedTransactionId.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          transactionId,
          'transactionId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (body.isEmpty || body.contains('\u0000')) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          body.isEmpty ? body : '<redacted>',
          'body',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    final normalizedReplyToEventId = replyToEventId?.trim();
    if (normalizedReplyToEventId != null &&
        (normalizedReplyToEventId.isEmpty ||
            normalizedReplyToEventId.contains('\u0000'))) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          replyToEventId,
          'replyToEventId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    final normalizedReplacementEventId = replacementEventId?.trim();
    if (normalizedReplacementEventId != null &&
        (normalizedReplacementEventId.isEmpty ||
            normalizedReplacementEventId.contains('\u0000'))) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError.value(
          replacementEventId,
          'replacementEventId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedReplyToEventId != null &&
        normalizedReplacementEventId != null) {
      return Future<MatrixRustSendResult>.error(
        ArgumentError(
          'A Matrix text event cannot be both a reply and a replacement.',
        ),
      );
    }
    return _enqueue<MatrixRustSendResult>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeSendTextOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          transactionId: normalizedTransactionId,
          body: body,
          replyToEventId: normalizedReplyToEventId,
          replacementEventId: normalizedReplacementEventId,
        ).call,
      );
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid send data.',
        );
      }
      final eventId = decoded['eventId'];
      if (eventId is! String || eventId.isEmpty) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid send data.',
        );
      }
      return MatrixRustSendResult(eventId: eventId);
    });
  }

  @override
  Future<Map<String, Object?>> encryptionRecoveryStatus() {
    return _recovery(action: 'status');
  }

  @override
  Future<Map<String, Object?>> createEncryptedBackup() {
    return _recovery(action: 'create_backup');
  }

  @override
  Future<Map<String, Object?>> recoverEncryption(String secret) {
    if (secret.isEmpty || secret.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          '<redacted>',
          'secret',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _recovery(action: 'recover', secret: secret);
  }

  @override
  Future<Map<String, Object?>> recoverEncryptedHistory() {
    return _recovery(action: 'recover_history');
  }

  @override
  Future<Map<String, Object?>> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) {
    if (path.isEmpty || path.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          path,
          'path',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (passphrase.isEmpty || passphrase.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          '<redacted>',
          'passphrase',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<Map<String, Object?>>(
      () => Isolate.run<Map<String, Object?>>(
        _MatrixNativeRoomKeyImportOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          path: path,
          passphrase: passphrase,
        ).call,
      ),
    );
  }

  Future<Map<String, Object?>> _recovery({
    required String action,
    String? secret,
  }) {
    return _enqueue<Map<String, Object?>>(
      () => Isolate.run<Map<String, Object?>>(
        _MatrixNativeRecoveryOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          action: action,
          secret: secret,
        ).call,
      ),
      priority: _MatrixOperationPriority.critical,
    );
  }

  @override
  Future<MatrixRustCreatedRoom> createRoom(
    MatrixSdkRoomCreationRequest request,
  ) {
    final payload = jsonEncode(<String, Object?>{
      'kind': request.kind.name,
      'name': request.name,
      'topic': request.topic,
      'invitees': request.invitees,
      'joinRule': request.joinRule,
      'encryptionEnabled': request.encryptionEnabled,
      'historyVisibility': request.historyVisibility,
      'canonicalAlias': request.canonicalAlias,
      'parentSpaceId': request.parentSpaceId,
    });
    return _enqueue<MatrixRustCreatedRoom>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeCreateRoomOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          payload: payload,
        ).call,
      );
      if (decoded is! Map<String, dynamic>) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room creation data.',
        );
      }
      final roomId = decoded['roomId'];
      final isDirect = decoded['isDirect'];
      if (roomId is! String || roomId.isEmpty || isDirect is! bool) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room creation data.',
        );
      }
      return MatrixRustCreatedRoom(roomId: roomId, isDirect: isDirect);
    });
  }

  @override
  Future<MatrixRustSessionDescriptor?> restoreSession() {
    return _enqueue<MatrixRustSessionDescriptor?>(() async {
      final value = await Isolate.run<Object?>(
        _MatrixNativeSessionOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          symbol: 'kite_matrix_client_restore_session',
          operation: 'session restore',
        ).call,
      );
      return value == null ? null : _decodeSessionDescriptor(value);
    });
  }

  @override
  Future<void> persistSession() {
    return _enqueue<void>(() async {
      await Isolate.run<Object?>(
        _MatrixNativeSessionOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          symbol: 'kite_matrix_client_persist_session',
          operation: 'session persistence',
        ).call,
      );
    });
  }

  @override
  Future<void> logout() {
    return _enqueue<void>(() async {
      await Isolate.run<Object?>(
        _MatrixNativeSessionOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          symbol: 'kite_matrix_client_logout',
          operation: 'session logout',
        ).call,
      );
    });
  }

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
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  }) {
    final normalizedMimeType = mimeType.trim();
    if (normalizedMimeType.isEmpty || normalizedMimeType.contains('\u0000')) {
      return Future<String>.error(
        ArgumentError.value(
          mimeType,
          'mimeType',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (bytes.isEmpty) {
      return Future<String>.error(
        ArgumentError.value(bytes, 'bytes', 'must not be empty'),
      );
    }
    final copiedBytes = Uint8List.fromList(bytes);
    return _enqueue<String>(() async {
      return Isolate.run<String>(
        _MatrixNativeUploadMediaOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          mimeType: normalizedMimeType,
          bytes: copiedBytes,
        ).call,
      );
    });
  }

  @override
  Future<Map<String, Uint8List>> prefetchMedia({
    required List<String> contentUris,
    required int width,
    required int height,
  }) {
    final normalizedUris = <String>[];
    final seen = <String>{};
    for (final contentUri in contentUris) {
      final normalized = contentUri.trim();
      if (!normalized.startsWith('mxc://') || normalized.contains('\u0000')) {
        return Future<Map<String, Uint8List>>.error(
          ArgumentError.value(
            contentUri,
            'contentUris',
            'must contain only valid Matrix content URIs without NUL bytes',
          ),
        );
      }
      if (seen.add(normalized)) normalizedUris.add(normalized);
    }
    if (normalizedUris.length > 32) {
      return Future<Map<String, Uint8List>>.error(
        ArgumentError.value(
          contentUris,
          'contentUris',
          'must contain at most 32 unique Matrix content URIs',
        ),
      );
    }
    if (normalizedUris.isEmpty) {
      return Future<Map<String, Uint8List>>.value(const <String, Uint8List>{});
    }
    if (width <= 0 || width > 4096) {
      return Future<Map<String, Uint8List>>.error(
        ArgumentError.value(width, 'width', 'must be between 1 and 4096'),
      );
    }
    if (height <= 0 || height > 4096) {
      return Future<Map<String, Uint8List>>.error(
        ArgumentError.value(height, 'height', 'must be between 1 and 4096'),
      );
    }
    final contentUrisJson = jsonEncode(normalizedUris);
    return _enqueue<Map<String, Uint8List>>(() async {
      return Isolate.run<Map<String, Uint8List>>(
        _MatrixNativePrefetchMediaOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          contentUrisJson: contentUrisJson,
          width: width,
          height: height,
        ).call,
      );
    }, priority: _MatrixOperationPriority.background);
  }

  @override
  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) {
    final normalizedContentUri = contentUri.trim();
    if (!normalizedContentUri.startsWith('mxc://') ||
        normalizedContentUri.contains('\u0000')) {
      return Future<Uint8List>.error(
        ArgumentError.value(
          contentUri,
          'contentUri',
          'must be a valid Matrix content URI without NUL bytes',
        ),
      );
    }
    if (width <= 0 || width > 4096) {
      return Future<Uint8List>.error(
        ArgumentError.value(width, 'width', 'must be between 1 and 4096'),
      );
    }
    if (height <= 0 || height > 4096) {
      return Future<Uint8List>.error(
        ArgumentError.value(height, 'height', 'must be between 1 and 4096'),
      );
    }
    final mediaSource = encryptedFile == null
        ? normalizedContentUri
        : jsonEncode(<String, Object?>{'file': encryptedFile});
    return _enqueue<Uint8List>(() async {
      return Isolate.run<Uint8List>(
        _MatrixNativeDownloadMediaOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          contentUri: mediaSource,
          width: width,
          height: height,
        ).call,
      );
    }, priority: _MatrixOperationPriority.interactive);
  }

  @override
  Future<Map<String, Object?>> profile({
    String? userId,
    required String action,
    String? value,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedAction = action.trim();
    if (normalizedUserId != null &&
        (normalizedUserId.isEmpty || normalizedUserId.contains('\u0000'))) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          userId,
          'userId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedAction.isEmpty || normalizedAction.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          action,
          'action',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (value?.contains('\u0000') ?? false) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          '<redacted>',
          'value',
          'must not contain NUL bytes',
        ),
      );
    }
    return _enqueue<Map<String, Object?>>(() async {
      return Isolate.run<Map<String, Object?>>(
        _MatrixNativeProfileOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          userId: normalizedUserId,
          action: normalizedAction,
          value: value,
        ).call,
      );
    });
  }

  @override
  Future<Map<String, Object?>> roomSettings({
    required String roomId,
    required String action,
    String? value,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedAction = action.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedAction.isEmpty || normalizedAction.contains('\u0000')) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          action,
          'action',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (value?.contains('\u0000') ?? false) {
      return Future<Map<String, Object?>>.error(
        ArgumentError.value(
          '<redacted>',
          'value',
          'must not contain NUL bytes',
        ),
      );
    }
    return _enqueue<Map<String, Object?>>(() async {
      return Isolate.run<Map<String, Object?>>(
        _MatrixNativeRoomSettingsOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          action: normalizedAction,
          value: value,
        ).call,
      );
    });
  }

  @override
  Future<void> setRoomFavourite({
    required String roomId,
    required bool isFavourite,
  }) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeSetRoomFavouriteOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          isFavourite: isFavourite,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['isFavourite'] != isFavourite) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid favourite state.',
        );
      }
    });
  }

  @override
  Future<void> respondToInvite({required String roomId, required bool accept}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeRespondInviteOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          accept: accept,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['accepted'] != accept) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid invite state.',
        );
      }
    });
  }

  @override
  Future<void> markRoomRead({required String roomId, required String eventId}) {
    final normalizedRoomId = roomId.trim();
    final normalizedEventId = eventId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedEventId.isEmpty || normalizedEventId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          eventId,
          'eventId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeMarkRoomReadOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          eventId: normalizedEventId,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['eventId'] != normalizedEventId) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid read receipt state.',
        );
      }
    });
  }

  @override
  Future<List<MatrixRustRoomMember>> roomMembers({required String roomId}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<List<MatrixRustRoomMember>>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<List<MatrixRustRoomMember>>(() async {
      final decoded = await Isolate.run<Map<String, Object?>>(
        _MatrixNativeRoomMembersOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
        ).call,
      );
      if (decoded['roomId'] != normalizedRoomId ||
          decoded['members'] is! List) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid room member data.',
        );
      }
      final members = <MatrixRustRoomMember>[];
      for (final value in decoded['members'] as List) {
        if (value is! Map<String, dynamic>) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage:
                'The Matrix native bridge returned invalid room member data.',
          );
        }
        final userId = value['userId'];
        final displayName = value['displayName'];
        final powerLevel = value['powerLevel'];
        if (userId is! String ||
            userId.isEmpty ||
            displayName is! String ||
            displayName.isEmpty ||
            powerLevel is! int) {
          throw const MatrixRustNativeException(
            code: 'invalid_native_response',
            publicMessage:
                'The Matrix native bridge returned invalid room member data.',
          );
        }
        members.add(
          MatrixRustRoomMember(
            userId: userId,
            displayName: displayName,
            powerLevel: powerLevel,
          ),
        );
      }
      return List<MatrixRustRoomMember>.unmodifiable(members);
    });
  }

  @override
  Future<void> inviteRoomMember({
    required String roomId,
    required String userId,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedUserId.isEmpty || normalizedUserId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          userId,
          'userId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeInviteRoomMemberOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          userId: normalizedUserId,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['userId'] != normalizedUserId) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage:
              'The Matrix native bridge returned invalid member invite data.',
        );
      }
    });
  }

  @override
  Future<MatrixRustRoomMemberPermissions> roomMemberPermissions({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedActorUserId = actorUserId.trim();
    final normalizedTargetUserId = targetUserId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<MatrixRustRoomMemberPermissions>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedActorUserId.isEmpty ||
        normalizedActorUserId.contains('\u0000')) {
      return Future<MatrixRustRoomMemberPermissions>.error(
        ArgumentError.value(
          actorUserId,
          'actorUserId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedTargetUserId.isEmpty ||
        normalizedTargetUserId.contains('\u0000')) {
      return Future<MatrixRustRoomMemberPermissions>.error(
        ArgumentError.value(
          targetUserId,
          'targetUserId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<MatrixRustRoomMemberPermissions>(() async {
      final decoded = await Isolate.run<Map<String, Object?>>(
        _MatrixNativeRoomMemberPermissionsOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          actorUserId: normalizedActorUserId,
          targetUserId: normalizedTargetUserId,
        ).call,
      );
      final actorPowerLevel = decoded['actorPowerLevel'];
      final canInvite = decoded['canInvite'];
      final canChangePowerLevel = decoded['canChangePowerLevel'];
      final canKick = decoded['canKick'];
      final canBan = decoded['canBan'];
      final canUnban = decoded['canUnban'];
      if (decoded['roomId'] != normalizedRoomId ||
          decoded['targetUserId'] != normalizedTargetUserId ||
          actorPowerLevel is! int ||
          canInvite is! bool ||
          canChangePowerLevel is! bool ||
          canKick is! bool ||
          canBan is! bool ||
          canUnban is! bool) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid room member permissions.',
        );
      }
      return MatrixRustRoomMemberPermissions(
        actorPowerLevel: actorPowerLevel,
        canInvite: canInvite,
        canChangePowerLevel: canChangePowerLevel,
        canKick: canKick,
        canBan: canBan,
        canUnban: canUnban,
      );
    });
  }

  @override
  Future<void> moderateRoomMember({
    required String roomId,
    required String userId,
    required String action,
    int powerLevel = 0,
    String? reason,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedUserId = userId.trim();
    final normalizedAction = action.trim();
    final normalizedReason = reason?.trim() ?? '';
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedUserId.isEmpty || normalizedUserId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          userId,
          'userId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (!const <String>{
      'set_power_level',
      'kick',
      'ban',
      'unban',
    }.contains(normalizedAction)) {
      return Future<void>.error(
        ArgumentError.value(
          action,
          'action',
          'must be a supported moderation action',
        ),
      );
    }
    if (normalizedReason.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          '<redacted>',
          'reason',
          'must not contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeModerateRoomMemberOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          userId: normalizedUserId,
          action: normalizedAction,
          powerLevel: powerLevel,
          reason: normalizedReason,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['userId'] != normalizedUserId ||
          decoded['action'] != normalizedAction) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid room moderation state.',
        );
      }
    });
  }

  @override
  Future<void> reportContent({
    required String roomId,
    required String eventId,
    String? reason,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedEventId = eventId.trim();
    final normalizedReason = reason?.trim() ?? '';
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedEventId.isEmpty || normalizedEventId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          eventId,
          'eventId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedReason.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          '<redacted>',
          'reason',
          'must not contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeReportContentOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          eventId: normalizedEventId,
          reason: normalizedReason,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['eventId'] != normalizedEventId) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid event reporting state.',
        );
      }
    });
  }

  @override
  Future<void> redactEvent({
    required String roomId,
    required String eventId,
    required String transactionId,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedEventId = eventId.trim();
    final normalizedTransactionId = transactionId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedEventId.isEmpty || normalizedEventId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          eventId,
          'eventId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (normalizedTransactionId.isEmpty ||
        normalizedTransactionId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          transactionId,
          'transactionId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeRedactEventOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          eventId: normalizedEventId,
          transactionId: normalizedTransactionId,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['eventId'] != normalizedEventId) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid event redaction state.',
        );
      }
    }, priority: _MatrixOperationPriority.interactive);
  }

  @override
  Future<void> manageRoom({
    required String roomId,
    required String action,
    String? userId,
    String? reason,
  }) {
    final normalizedRoomId = roomId.trim();
    final normalizedAction = action.trim();
    final normalizedUserId = userId?.trim() ?? '';
    final normalizedReason = reason?.trim() ?? '';
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          roomId,
          'roomId',
          'must not be empty or contain NUL bytes',
        ),
      );
    }
    if (!const <String>{
      'report_room',
      'report_user',
      'leave',
      'forget',
    }.contains(normalizedAction)) {
      return Future<void>.error(
        ArgumentError.value(
          action,
          'action',
          'must be a supported room action',
        ),
      );
    }
    if (normalizedUserId.contains('\u0000') ||
        (normalizedAction == 'report_user' && normalizedUserId.isEmpty)) {
      return Future<void>.error(
        ArgumentError.value(
          normalizedUserId.isEmpty ? normalizedUserId : '<redacted>',
          'userId',
          'must identify a valid Matrix user without NUL bytes',
        ),
      );
    }
    if (normalizedReason.contains('\u0000')) {
      return Future<void>.error(
        ArgumentError.value(
          '<redacted>',
          'reason',
          'must not contain NUL bytes',
        ),
      );
    }
    return _enqueue<void>(() async {
      final decoded = await Isolate.run<Object?>(
        _MatrixNativeManageRoomOperation(
          libraryPath: libraryPath,
          address: _requireAddress(),
          roomId: normalizedRoomId,
          action: normalizedAction,
          userId: normalizedUserId,
          reason: normalizedReason,
        ).call,
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['roomId'] != normalizedRoomId ||
          decoded['action'] != normalizedAction ||
          (normalizedAction == 'report_user' &&
              decoded['userId'] != normalizedUserId)) {
        throw const MatrixRustNativeException(
          code: 'invalid_native_response',
          publicMessage: 'The Matrix native bridge returned invalid room management state.',
        );
      }
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
    }, priority: _MatrixOperationPriority.interactive);
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

  Future<T> _enqueue<T>(
    Future<T> Function() operation, {
    _MatrixOperationPriority priority = _MatrixOperationPriority.normal,
  }) {
    return _operations.enqueue(operation, priority: priority);
  }
}

final class MatrixRustSdkBoundary
    implements
        MatrixSdkBoundary,
        MatrixSdkPasswordAuthenticator,
        MatrixSdkTextMessageSender,
        MatrixSdkMediaManager,
        MatrixSdkMediaPrefetcher,
        MatrixSdkProfileManager,
        MatrixSdkEncryptionRecoveryManager,
        MatrixSdkDeviceManager,
        MatrixSdkRoomCreator,
        MatrixSdkRoomSettingsManager,
        MatrixSdkRoomLifecycleManager,
        MatrixSdkTimelineModerationManager,
        MatrixSdkTimelineRedactionManager,
        MatrixSdkRoomMemberDirectory,
        MatrixSdkRoomMemberInviter,
        MatrixSdkRoomMemberModerator,
        MatrixSdkRoomFavouriteManager,
        MatrixSdkRoomInviteManager,
        MatrixSdkRoomReadManager {
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
  MatrixSdkStoreConfiguration? _openedStore;
  final _operations = _MatrixSerialOperationQueue();
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
      final client = _client;
      if (client != null) {
        final openedStore = _openedStore;
        if (openedStore == null || !_sameStore(openedStore, store)) {
          throw StateError(
            'Matrix Rust SDK boundary is already open for another store',
          );
        }
        return;
      }
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
      _openedStore = store;
    });
  }

  @override
  Future<MatrixSdkPasswordLoginResult> loginWithPassword({
    required String username,
    required String password,
  }) {
    return _enqueue<MatrixSdkPasswordLoginResult>(() async {
      final result = await _requireClient().loginWithPassword(
        username: username,
        password: password,
      );
      return MatrixSdkPasswordLoginResult(
        userId: result.userId,
        deviceId: result.deviceId,
      );
    });
  }

  @override
  Future<String> sendTextMessage({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
    String? replacementEventId,
  }) {
    return _enqueue<String>(() async {
      final result = await _requireClient().sendText(
        roomId: roomId,
        transactionId: transactionId,
        body: body,
        replyToEventId: replyToEventId,
        replacementEventId: replacementEventId,
      );
      return result.eventId;
    });
  }

  @override
  Future<String> uploadMedia({
    required String mimeType,
    required Uint8List bytes,
  }) {
    return _enqueue<String>(() async {
      final client = _requireClient();
      if (client is! MatrixRustMediaClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support media uploads',
        );
      }
      final contentUri = await (client as MatrixRustMediaClient).uploadMedia(
        mimeType: mimeType,
        bytes: bytes,
      );
      if (!contentUri.startsWith('mxc://') || contentUri.length <= 6) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned an invalid media URI',
        );
      }
      return contentUri;
    });
  }

  @override
  Future<Map<String, Uint8List>> prefetchMedia({
    required List<String> contentUris,
    required int width,
    required int height,
  }) {
    return _enqueue<Map<String, Uint8List>>(() async {
      final client = _requireClient();
      if (client is! MatrixRustMediaPrefetchClient) {
        return const <String, Uint8List>{};
      }
      return (client as MatrixRustMediaPrefetchClient).prefetchMedia(
        contentUris: contentUris,
        width: width,
        height: height,
      );
    }, priority: _MatrixOperationPriority.background);
  }

  @override
  Future<Uint8List> downloadMedia({
    required String contentUri,
    Map<String, Object?>? encryptedFile,
    required int width,
    required int height,
  }) {
    return _enqueue<Uint8List>(() async {
      final client = _requireClient();
      if (client is! MatrixRustMediaClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support media downloads',
        );
      }
      final bytes = await (client as MatrixRustMediaClient).downloadMedia(
        contentUri: contentUri,
        encryptedFile: encryptedFile,
        width: width,
        height: height,
      );
      if (bytes.isEmpty) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned empty media data',
        );
      }
      return bytes;
    }, priority: _MatrixOperationPriority.interactive);
  }

  @override
  Future<MatrixSdkEncryptionRecoveryStatus> encryptionRecoveryStatus() {
    return _encryptionRecovery((client) => client.encryptionRecoveryStatus());
  }

  @override
  Future<MatrixSdkEncryptionRecoveryStatus> createEncryptedBackup() {
    return _encryptionRecovery((client) => client.createEncryptedBackup());
  }

  @override
  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryption(String secret) {
    return _encryptionRecovery((client) => client.recoverEncryption(secret));
  }

  @override
  Future<MatrixSdkEncryptionRecoveryStatus> recoverEncryptedHistory() {
    return _encryptionRecovery((client) => client.recoverEncryptedHistory());
  }

  @override
  Future<MatrixSdkRoomKeyImportResult> importRoomKeyBackup({
    required String path,
    required String passphrase,
  }) {
    return _enqueue<MatrixSdkRoomKeyImportResult>(() async {
      final client = _requireClient();
      if (client is! MatrixRustEncryptionRecoveryClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support encryption recovery',
        );
      }
      final data = await (client as MatrixRustEncryptionRecoveryClient)
          .importRoomKeyBackup(path: path, passphrase: passphrase);
      final importedCount = data['importedCount'];
      final totalCount = data['totalCount'];
      if (importedCount is! int ||
          totalCount is! int ||
          importedCount < 0 ||
          totalCount < importedCount) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid room-key import data',
        );
      }
      return MatrixSdkRoomKeyImportResult(
        importedCount: importedCount,
        totalCount: totalCount,
      );
    });
  }

  Future<MatrixSdkEncryptionRecoveryStatus> _encryptionRecovery(
    Future<Map<String, Object?>> Function(
      MatrixRustEncryptionRecoveryClient client,
    )
    operation,
  ) {
    return _enqueue<MatrixSdkEncryptionRecoveryStatus>(() async {
      final client = _requireClient();
      if (client is! MatrixRustEncryptionRecoveryClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support encryption recovery',
        );
      }
      final data = await operation(
        client as MatrixRustEncryptionRecoveryClient,
      );
      final recoveryState = switch (data['recoveryState']) {
        'unknown' => MatrixSdkEncryptionRecoveryState.unknown,
        'enabled' => MatrixSdkEncryptionRecoveryState.enabled,
        'disabled' => MatrixSdkEncryptionRecoveryState.disabled,
        'incomplete' => MatrixSdkEncryptionRecoveryState.incomplete,
        _ => throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid recovery state',
        ),
      };
      final backupState = switch (data['backupState']) {
        'unknown' => MatrixSdkEncryptionBackupState.unknown,
        'creating' => MatrixSdkEncryptionBackupState.creating,
        'enabling' => MatrixSdkEncryptionBackupState.enabling,
        'resuming' => MatrixSdkEncryptionBackupState.resuming,
        'enabled' => MatrixSdkEncryptionBackupState.enabled,
        'downloading' => MatrixSdkEncryptionBackupState.downloading,
        'disabling' => MatrixSdkEncryptionBackupState.disabling,
        _ => throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid backup state',
        ),
      };
      final backupExistsOnServer = data['backupExistsOnServer'];
      if (backupExistsOnServer is! bool) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid backup availability',
        );
      }
      return MatrixSdkEncryptionRecoveryStatus(
        recoveryState: recoveryState,
        backupState: backupState,
        backupExistsOnServer: backupExistsOnServer,
      );
    }, priority: _MatrixOperationPriority.critical);
  }

  @override
  Future<MatrixSdkProfileDetails> loadOwnProfile() {
    return _enqueue<MatrixSdkProfileDetails>(() async {
      return _profileDetails(await _profile(action: 'get'));
    });
  }

  @override
  Future<MatrixSdkProfileDetails> loadProfile(String userId) {
    return _enqueue<MatrixSdkProfileDetails>(() async {
      return _profileDetails(
        await _profile(userId: userId, action: 'get'),
        expectedUserId: userId,
      );
    });
  }

  @override
  Future<List<MatrixSdkUserSearchResult>> searchUsers(String query) {
    return _enqueue<List<MatrixSdkUserSearchResult>>(() async {
      final decoded = await _profile(action: 'search', value: query);
      final rawResults = decoded['results'];
      if (rawResults is! List<Object?>) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid user search data',
        );
      }
      return <MatrixSdkUserSearchResult>[
        for (final raw in rawResults) _userSearchResult(raw),
      ];
    });
  }

  MatrixSdkUserSearchResult _userSearchResult(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid user search data',
      );
    }
    final userId = raw['userId'];
    final displayName = raw['displayName'];
    final avatarUrl = raw['avatarUrl'];
    if (userId is! String ||
        userId.trim().isEmpty ||
        (displayName != null && displayName is! String) ||
        (avatarUrl != null && avatarUrl is! String)) {
      throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid user search data',
      );
    }
    return MatrixSdkUserSearchResult(
      userId: userId,
      displayName: displayName as String?,
      avatarUrl: avatarUrl as String?,
    );
  }

  @override
  Future<Set<String>> loadIgnoredUserIds() {
    return _enqueue<Set<String>>(() async {
      final decoded = await _profile(action: 'ignored_users');
      final rawUserIds = decoded['userIds'];
      if (rawUserIds is! List<Object?>) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid ignored-user data',
        );
      }
      final userIds = <String>{};
      for (final rawUserId in rawUserIds) {
        if (rawUserId is! String ||
            rawUserId.trim() != rawUserId ||
            rawUserId.isEmpty) {
          throw const MatrixSdkContractException(
            'Matrix Rust client returned invalid ignored-user data',
          );
        }
        userIds.add(rawUserId);
      }
      return Set<String>.unmodifiable(userIds);
    });
  }

  @override
  Future<void> setUserIgnored(String userId, bool ignored) {
    return _enqueue<void>(() async {
      final decoded = await _profile(
        userId: userId,
        action: 'set_ignored',
        value: ignored.toString(),
      );
      if (decoded['action'] != 'set_ignored' ||
          decoded['userId'] != userId ||
          decoded['ignored'] != ignored) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid ignored-user state',
        );
      }
    });
  }

  @override
  Future<List<MatrixSdkSessionDeviceDetails>> loadDevices() {
    return _enqueue<List<MatrixSdkSessionDeviceDetails>>(() async {
      final decoded = await _profile(action: 'devices');
      final rawDevices = decoded['devices'];
      if (rawDevices is! List<Object?>) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid device data',
        );
      }
      return List<MatrixSdkSessionDeviceDetails>.unmodifiable(
        rawDevices.map(_sessionDeviceDetails),
      );
    });
  }

  MatrixSdkSessionDeviceDetails _sessionDeviceDetails(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid device data',
      );
    }
    final deviceId = raw['deviceId'];
    final isCurrent = raw['isCurrent'];
    final verification = raw['verification'];
    final displayName = raw['displayName'];
    final lastSeenAtMs = raw['lastSeenAtMs'];
    if (deviceId is! String ||
        deviceId.trim() != deviceId ||
        deviceId.isEmpty ||
        isCurrent is! bool ||
        verification is! String ||
        (displayName != null && displayName is! String) ||
        (lastSeenAtMs != null && lastSeenAtMs is! int)) {
      throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid device data',
      );
    }
    final isVerified = switch (verification) {
      'verified' => true,
      'unverified' => false,
      'unknown' => null,
      _ => throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid device verification data',
      ),
    };
    return MatrixSdkSessionDeviceDetails(
      deviceId: deviceId,
      isCurrent: isCurrent,
      isVerified: isVerified,
      displayName: displayName as String?,
      lastSeenAt: lastSeenAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              lastSeenAtMs as int,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> signOutDevice(String deviceId, {required String password}) {
    return _enqueue<void>(() async {
      final decoded = await _profile(
        userId: deviceId,
        action: 'delete_device',
        value: password,
      );
      if (decoded['action'] != 'delete_device' ||
          decoded['deviceId'] != deviceId) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid device sign-out state',
        );
      }
    });
  }

  @override
  Future<void> updateDisplayName(String displayName) =>
      _updateProfile(action: 'set_display_name', value: displayName);

  @override
  Future<void> updateAvatar(String? avatarUrl) =>
      _updateProfile(action: 'set_avatar', value: avatarUrl);

  @override
  Future<String> openDirectMessage(String userId) {
    return _enqueue<String>(() async {
      final decoded = await _profile(userId: userId, action: 'open_direct');
      final roomId = decoded['roomId'];
      if (roomId is! String || roomId.trim().isEmpty) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned an invalid direct-message room',
        );
      }
      return roomId;
    });
  }

  Future<Map<String, Object?>> _profile({
    String? userId,
    required String action,
    String? value,
  }) async {
    final client = _requireClient();
    if (client is! MatrixRustProfileClient) {
      throw const MatrixSdkContractException(
        'Matrix Rust client does not support profile management',
      );
    }
    return (client as MatrixRustProfileClient).profile(
      userId: userId,
      action: action,
      value: value,
    );
  }

  MatrixSdkProfileDetails _profileDetails(
    Map<String, Object?> decoded, {
    String? expectedUserId,
  }) {
    final userId = decoded['userId'];
    final displayName = decoded['displayName'];
    final avatarUrl = decoded['avatarUrl'];
    if (userId is! String ||
        userId.trim().isEmpty ||
        (expectedUserId != null && userId != expectedUserId) ||
        (displayName != null && displayName is! String) ||
        (avatarUrl != null && avatarUrl is! String)) {
      throw const MatrixSdkContractException(
        'Matrix Rust client returned invalid profile data',
      );
    }
    return MatrixSdkProfileDetails(
      userId: userId,
      displayName: displayName as String?,
      avatarUrl: avatarUrl as String?,
    );
  }

  Future<void> _updateProfile({required String action, String? value}) {
    return _enqueue<void>(() async {
      final decoded = await _profile(action: action, value: value);
      if (decoded['action'] != action) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid profile state',
        );
      }
    });
  }

  @override
  Future<MatrixSdkCreatedRoom> createRoom(
    MatrixSdkRoomCreationRequest request,
  ) {
    return _enqueue<MatrixSdkCreatedRoom>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomCreator) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room creation',
        );
      }
      final created = await (client as MatrixRustRoomCreator).createRoom(
        request,
      );
      return MatrixSdkCreatedRoom(
        roomId: created.roomId,
        isDirect: created.isDirect,
      );
    });
  }

  @override
  Future<MatrixSdkRoomDetails> roomDetails(String roomId) {
    return _enqueue<MatrixSdkRoomDetails>(() async {
      final decoded = await _roomSettings(roomId: roomId, action: 'get');
      final returnedRoomId = decoded['roomId'];
      final name = decoded['name'];
      final topic = decoded['topic'];
      final avatarUrl = decoded['avatarUrl'];
      final canonicalAlias = decoded['canonicalAlias'];
      final joinRule = decoded['joinRule'];
      final encryptionEnabled = decoded['encryptionEnabled'];
      final historyVisibility = decoded['historyVisibility'];
      final notificationMode = decoded['notificationMode'];
      final isDirect = decoded['isDirect'];
      final directUserIds = decoded['directUserIds'];
      if (returnedRoomId is! String ||
          returnedRoomId.isEmpty ||
          (name != null && name is! String) ||
          (topic != null && topic is! String) ||
          (avatarUrl != null && avatarUrl is! String) ||
          (canonicalAlias != null && canonicalAlias is! String) ||
          joinRule is! String ||
          encryptionEnabled is! bool ||
          historyVisibility is! String ||
          notificationMode is! String ||
          isDirect is! bool ||
          directUserIds is! List ||
          directUserIds.any((value) => value is! String)) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid room settings',
        );
      }
      return MatrixSdkRoomDetails(
        roomId: returnedRoomId,
        name: name as String?,
        topic: topic as String?,
        avatarUrl: avatarUrl as String?,
        canonicalAlias: canonicalAlias as String?,
        joinRule: joinRule,
        encryptionEnabled: encryptionEnabled,
        historyVisibility: historyVisibility,
        notificationMode: notificationMode,
        isDirect: isDirect,
        directUserIds: directUserIds.cast<String>(),
      );
    });
  }

  @override
  Future<void> setRoomName(String roomId, String? name) =>
      _setRoomSetting(roomId: roomId, action: 'set_name', value: name);

  @override
  Future<void> setRoomTopic(String roomId, String? topic) =>
      _setRoomSetting(roomId: roomId, action: 'set_topic', value: topic);

  @override
  Future<void> setRoomAvatar(String roomId, String? avatarUrl) =>
      _setRoomSetting(roomId: roomId, action: 'set_avatar', value: avatarUrl);

  @override
  Future<void> setRoomCanonicalAlias(String roomId, String? canonicalAlias) =>
      _setRoomSetting(
        roomId: roomId,
        action: 'set_canonical_alias',
        value: canonicalAlias,
      );

  @override
  Future<void> setRoomJoinRule(String roomId, String joinRule) =>
      _setRoomSetting(roomId: roomId, action: 'set_join_rule', value: joinRule);

  @override
  Future<void> enableRoomEncryption(String roomId) =>
      _setRoomSetting(roomId: roomId, action: 'enable_encryption');

  @override
  Future<void> setRoomHistoryVisibility(String roomId, String visibility) =>
      _setRoomSetting(
        roomId: roomId,
        action: 'set_history_visibility',
        value: visibility,
      );

  @override
  Future<void> setRoomNotificationMode(String roomId, String mode) =>
      _setRoomSetting(
        roomId: roomId,
        action: 'set_notification_mode',
        value: mode,
      );

  Future<Map<String, Object?>> _roomSettings({
    required String roomId,
    required String action,
    String? value,
  }) async {
    final client = _requireClient();
    if (client is! MatrixRustRoomSettingsClient) {
      throw const MatrixSdkContractException(
        'Matrix Rust client does not support room settings',
      );
    }
    return (client as MatrixRustRoomSettingsClient).roomSettings(
      roomId: roomId,
      action: action,
      value: value,
    );
  }

  Future<void> _setRoomSetting({
    required String roomId,
    required String action,
    String? value,
  }) {
    return _enqueue<void>(() async {
      final decoded = await _roomSettings(
        roomId: roomId,
        action: action,
        value: value,
      );
      if (decoded['roomId'] != roomId || decoded['action'] != action) {
        throw const MatrixSdkContractException(
          'Matrix Rust client returned invalid room settings state',
        );
      }
    });
  }

  @override
  Future<void> setRoomFavourite(String roomId, bool isFavourite) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomFavouriteClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room favourites',
        );
      }
      await (client as MatrixRustRoomFavouriteClient).setRoomFavourite(
        roomId: roomId,
        isFavourite: isFavourite,
      );
    });
  }

  @override
  Future<void> respondToRoomInvite(String roomId, bool accept) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomInviteClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room invites',
        );
      }
      await (client as MatrixRustRoomInviteClient).respondToInvite(
        roomId: roomId,
        accept: accept,
      );
    });
  }

  @override
  Future<void> markRoomRead(String roomId, String eventId) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomReadClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support read receipts',
        );
      }
      await (client as MatrixRustRoomReadClient).markRoomRead(
        roomId: roomId,
        eventId: eventId,
      );
    });
  }

  @override
  Future<List<MatrixSdkRoomMember>> roomMembers(String roomId) {
    return _enqueue<List<MatrixSdkRoomMember>>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomMembersClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room member lookup',
        );
      }
      final memberClient = client as MatrixRustRoomMembersClient;
      final members = await memberClient.roomMembers(roomId: roomId);
      return List<MatrixSdkRoomMember>.unmodifiable(
        members.map(
          (member) => MatrixSdkRoomMember(
            userId: member.userId,
            displayName: member.displayName,
            powerLevel: member.powerLevel,
          ),
        ),
      );
    });
  }

  @override
  Future<void> inviteRoomMember(String roomId, String userId) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomMemberInviterClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room member invitations',
        );
      }
      await (client as MatrixRustRoomMemberInviterClient).inviteRoomMember(
        roomId: roomId,
        userId: userId,
      );
    });
  }

  @override
  Future<bool> canModerateRoomMember({
    required String roomId,
    required String actorUserId,
    required String targetUserId,
    required MatrixSdkRoomMemberAction action,
    int? requestedPowerLevel,
  }) {
    return _enqueue<bool>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomMemberModeratorClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room member moderation',
        );
      }
      final permissions = await (client as MatrixRustRoomMemberModeratorClient)
          .roomMemberPermissions(
            roomId: roomId,
            actorUserId: actorUserId,
            targetUserId: targetUserId,
          );
      return switch (action) {
        MatrixSdkRoomMemberAction.invite => permissions.canInvite,
        MatrixSdkRoomMemberAction.changePowerLevel =>
          permissions.canChangePowerLevel &&
              requestedPowerLevel != null &&
              requestedPowerLevel <= permissions.actorPowerLevel,
        MatrixSdkRoomMemberAction.kick => permissions.canKick,
        MatrixSdkRoomMemberAction.ban => permissions.canBan,
        MatrixSdkRoomMemberAction.unban => permissions.canUnban,
      };
    });
  }

  @override
  Future<void> setRoomMemberPowerLevel(
    String roomId,
    String userId,
    int powerLevel,
  ) {
    return _moderateRoomMember(
      roomId: roomId,
      userId: userId,
      action: 'set_power_level',
      powerLevel: powerLevel,
    );
  }

  @override
  Future<void> kickRoomMember(String roomId, String userId) {
    return _moderateRoomMember(roomId: roomId, userId: userId, action: 'kick');
  }

  @override
  Future<void> banRoomMember(String roomId, String userId, {String? reason}) {
    return _moderateRoomMember(
      roomId: roomId,
      userId: userId,
      action: 'ban',
      reason: reason,
    );
  }

  @override
  Future<void> unbanRoomMember(String roomId, String userId) {
    return _moderateRoomMember(roomId: roomId, userId: userId, action: 'unban');
  }

  @override
  Future<void> reportEvent(String roomId, String eventId, {String? reason}) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustTimelineModerationClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support event reporting',
        );
      }
      await (client as MatrixRustTimelineModerationClient).reportContent(
        roomId: roomId,
        eventId: eventId,
        reason: reason,
      );
    });
  }

  @override
  Future<void> redactEvent(
    String roomId,
    String eventId, {
    required String transactionId,
  }) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustTimelineRedactionClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support event redaction',
        );
      }
      await (client as MatrixRustTimelineRedactionClient).redactEvent(
        roomId: roomId,
        eventId: eventId,
        transactionId: transactionId,
      );
    }, priority: _MatrixOperationPriority.interactive);
  }

  @override
  Future<void> reportRoom(String roomId, {String? reason}) {
    return _manageRoom(roomId: roomId, action: 'report_room', reason: reason);
  }

  @override
  Future<void> reportUser(String roomId, String userId, {String? reason}) {
    return _manageRoom(
      roomId: roomId,
      action: 'report_user',
      userId: userId,
      reason: reason,
    );
  }

  @override
  Future<void> leaveRoom(String roomId) {
    return _manageRoom(roomId: roomId, action: 'leave');
  }

  @override
  Future<void> forgetRoom(String roomId) {
    return _manageRoom(roomId: roomId, action: 'forget');
  }

  Future<void> _manageRoom({
    required String roomId,
    required String action,
    String? userId,
    String? reason,
  }) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomLifecycleClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room management',
        );
      }
      await (client as MatrixRustRoomLifecycleClient).manageRoom(
        roomId: roomId,
        action: action,
        userId: userId,
        reason: reason,
      );
    });
  }

  Future<void> _moderateRoomMember({
    required String roomId,
    required String userId,
    required String action,
    int powerLevel = 0,
    String? reason,
  }) {
    return _enqueue<void>(() async {
      final client = _requireClient();
      if (client is! MatrixRustRoomMemberModeratorClient) {
        throw const MatrixSdkContractException(
          'Matrix Rust client does not support room member moderation',
        );
      }
      await (client as MatrixRustRoomMemberModeratorClient).moderateRoomMember(
        roomId: roomId,
        userId: userId,
        action: action,
        powerLevel: powerLevel,
        reason: reason,
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
    }, priority: _MatrixOperationPriority.critical);
  }

  @override
  Future<void> stopSync() {
    return _enqueue(_stopSync, priority: _MatrixOperationPriority.critical);
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
    }, priority: _MatrixOperationPriority.interactive);
  }

  @override
  Future<void> close() {
    return _enqueue(() async {
      await _stopSync();
      final client = _client;
      if (client == null) return;
      await client.close();
      if (identical(_client, client)) {
        _client = null;
        _openedStore = null;
      }
    });
  }

  Future<void> _runSyncLoop(
    MatrixRustClient client,
    MatrixSdkSyncConfiguration configuration,
  ) async {
    var firstRequest = true;
    var failureAttempt = 0;
    var syncToken = configuration.resumeFromCursor;
    while (_syncRequested && identical(_client, client)) {
      final trace = logger?.trace(
        DiagnosticFlow.sync,
        DiagnosticOperation.syncCycle,
      );
      trace?.log(LogLevel.info, DiagnosticEvent.started);
      try {
        final isColdRequest = firstRequest && syncToken == null;
        final payload = await client.syncOnce(
          timeout: firstRequest ? Duration.zero : _matrixRustSyncPollTimeout,
          timelineEventLimit: isColdRequest
              ? configuration.initialTimelineEventLimit
              : configuration.timelineEventLimit,
          since: syncToken,
        );
        if (!_syncRequested || !identical(_client, client)) return;
        final syncFailureCodeIndex = await Isolate.run<int?>(() {
          return _decodeMatrixRustSyncFailure(payload)?.code.index;
        });
        final syncFailure = syncFailureCodeIndex == null
            ? null
            : _MatrixRustSyncFailure(
                _MatrixRustSyncFailureCode.values[syncFailureCodeIndex],
              );
        if (syncFailure != null) {
          if (syncFailure.code == _MatrixRustSyncFailureCode.unknownPosition &&
              syncToken != null) {
            syncToken = null;
            failureAttempt = 0;
            continue;
          }
          throw syncFailure;
        }
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
          roomChunkSize: isColdRequest
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
        final isPermanentPayloadFailure =
            error is FormatException ||
            (error is _MatrixRustSyncFailure && error.isPermanent);
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
        final syncError =
            error is _MatrixRustSyncFailure && error.isSessionExpired
            ? const MatrixSessionExpiredException()
            : error;
        _syncBatches.addError(
          isPermanentPayloadFailure
              ? MatrixNonRetryableSyncException(syncError)
              : syncError,
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
          invites: isFinalChunk
              ? syncBatch.invites
              : const <MatrixRoomInvite>[],
          removedInviteRoomIds: isFinalChunk
              ? syncBatch.removedInviteRoomIds
              : const <String>[],
          removedRoomIds: isFinalChunk
              ? syncBatch.removedRoomIds
              : const <String>[],
          replaceInvites: isFinalChunk && syncBatch.replaceInvites,
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

  static bool _sameStore(
    MatrixSdkStoreConfiguration left,
    MatrixSdkStoreConfiguration right,
  ) {
    return left.accountId == right.accountId &&
        left.storePath == right.storePath &&
        left.encryptionKeyId == right.encryptionKeyId;
  }

  MatrixRustClient _requireClient() {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('Matrix Rust SDK client is not open');
    }
    return client;
  }

  Future<T> _enqueue<T>(
    Future<T> Function() operation, {
    _MatrixOperationPriority priority = _MatrixOperationPriority.normal,
  }) {
    return _operations.enqueue(operation, priority: priority);
  }
}
