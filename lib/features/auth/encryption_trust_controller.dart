import 'package:signals/signals.dart';

enum EncryptionTrustState {
  unknown,
  verified,
  unverifiedDevice,
  unverifiedUser,
}

final class RoomEncryptionTrust {
  RoomEncryptionTrust({
    required this.roomId,
    required this.isEncrypted,
    required this.trustState,
    required this.historySharingSupported,
    required this.historySharingEnabled,
  }) {
    final normalizedRoomId = roomId.trim();
    final separator = normalizedRoomId.indexOf(':');
    if (normalizedRoomId != roomId ||
        !normalizedRoomId.startsWith('!') ||
        separator <= 1 ||
        separator == normalizedRoomId.length - 1 ||
        normalizedRoomId.contains(RegExp(r'\s'))) {
      throw ArgumentError('Matrix room ID is invalid.');
    }
    if (!isEncrypted && trustState != EncryptionTrustState.unknown) {
      throw ArgumentError(
        'Unencrypted rooms cannot expose encrypted trust state.',
      );
    }
    if (!isEncrypted && historySharingSupported) {
      throw ArgumentError(
        'Unencrypted rooms cannot expose encrypted history sharing.',
      );
    }
    if (!historySharingSupported && historySharingEnabled) {
      throw ArgumentError(
        'Encrypted history sharing cannot be enabled when unsupported.',
      );
    }
  }

  final String roomId;
  final bool isEncrypted;
  final EncryptionTrustState trustState;
  final bool historySharingSupported;
  final bool historySharingEnabled;

  bool get requiresTrustWarning =>
      isEncrypted && trustState != EncryptionTrustState.verified;

  RoomEncryptionTrust copyWith({bool? historySharingEnabled}) {
    return RoomEncryptionTrust(
      roomId: roomId,
      isEncrypted: isEncrypted,
      trustState: trustState,
      historySharingSupported: historySharingSupported,
      historySharingEnabled:
          historySharingEnabled ?? this.historySharingEnabled,
    );
  }
}

abstract interface class EncryptionTrustGateway {
  /// Reads room encryption/trust from the audited Matrix SDK boundary.
  Future<RoomEncryptionTrust> loadRoomTrust(String roomId);

  /// Delegates encrypted-history-sharing policy to the Matrix SDK/server.
  Future<RoomEncryptionTrust> setHistorySharing({
    required String roomId,
    required bool enabled,
  });
}

final class EncryptionTrustController {
  EncryptionTrustController(this._gateway);

  final EncryptionTrustGateway _gateway;
  int _accountGeneration = 0;

  final state = signal<RoomEncryptionTrust?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  String? get warningMessage {
    final current = state.value;
    if (current == null || !current.isEncrypted) return null;
    return switch (current.trustState) {
      EncryptionTrustState.unverifiedDevice =>
        'This encrypted room includes an unverified device.',
      EncryptionTrustState.unverifiedUser =>
        'This encrypted room includes an unverified user.',
      EncryptionTrustState.unknown =>
        'This encrypted room has unknown verification state.',
      EncryptionTrustState.verified => null,
    };
  }

  bool resetForAccountChange() {
    _accountGeneration += 1;
    state.value = null;
    isBusy.value = false;
    errorMessage.value = null;
    return true;
  }

  Future<bool> load(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (!_isValidRoomId(normalizedRoomId)) {
      state.value = null;
      errorMessage.value = 'Choose a valid Matrix room.';
      return false;
    }
    if (state.value?.roomId != normalizedRoomId) {
      state.value = null;
    }
    return _run(
      () => _gateway.loadRoomTrust(normalizedRoomId),
      expectedRoomId: normalizedRoomId,
      failureMessage: 'Kite could not read encryption trust state.',
    );
  }

  Future<bool> setHistorySharing(bool enabled) async {
    final current = state.value;
    if (current == null || !current.isEncrypted) {
      errorMessage.value =
          'Open an encrypted room before changing history sharing.';
      return false;
    }
    if (!current.historySharingSupported) {
      errorMessage.value =
          'Encrypted history sharing is not supported in this room.';
      return false;
    }
    return _run(
      () =>
          _gateway.setHistorySharing(roomId: current.roomId, enabled: enabled),
      expectedRoomId: current.roomId,
      expectedHistorySharingEnabled: enabled,
      requireEncryptedHistorySharing: true,
      failureMessage: 'Kite could not update encrypted history sharing.',
    );
  }

  Future<bool> _run(
    Future<RoomEncryptionTrust> Function() action, {
    required String expectedRoomId,
    bool? expectedHistorySharingEnabled,
    bool requireEncryptedHistorySharing = false,
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    final generation = _accountGeneration;
    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (generation != _accountGeneration) return false;
      if (next.roomId != expectedRoomId ||
          (expectedHistorySharingEnabled != null &&
              next.historySharingEnabled != expectedHistorySharingEnabled) ||
          (requireEncryptedHistorySharing &&
              (!next.isEncrypted || !next.historySharingSupported))) {
        errorMessage.value = 'Kite received invalid encryption trust state.';
        return false;
      }
      state.value = next;
      return true;
    } catch (_) {
      if (generation == _accountGeneration) {
        errorMessage.value = failureMessage;
      }
      return false;
    } finally {
      if (generation == _accountGeneration) {
        isBusy.value = false;
      }
    }
  }

  bool _isValidRoomId(String roomId) {
    final separator = roomId.indexOf(':');
    return roomId.startsWith('!') &&
        separator > 1 &&
        separator < roomId.length - 1 &&
        !roomId.contains(RegExp(r'\s'));
  }

  void dispose() {
    _accountGeneration += 1;
    state.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
