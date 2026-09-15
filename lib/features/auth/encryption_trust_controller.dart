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
    if (roomId.trim().isEmpty) {
      throw ArgumentError.value(roomId, 'roomId');
    }
    if (!isEncrypted && trustState != EncryptionTrustState.unknown) {
      throw ArgumentError(
        'Unencrypted rooms cannot expose encrypted trust state.',
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
      trustState == EncryptionTrustState.unverifiedDevice ||
      trustState == EncryptionTrustState.unverifiedUser;

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

  final state = signal<RoomEncryptionTrust?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);

  String? get warningMessage {
    return switch (state.value?.trustState) {
      EncryptionTrustState.unverifiedDevice =>
        'This encrypted room includes an unverified device.',
      EncryptionTrustState.unverifiedUser =>
        'This encrypted room includes an unverified user.',
      EncryptionTrustState.unknown ||
      EncryptionTrustState.verified ||
      null => null,
    };
  }

  Future<bool> load(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (!_isValidRoomId(normalizedRoomId)) {
      errorMessage.value = 'Choose a valid Matrix room.';
      return false;
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
      failureMessage: 'Kite could not update encrypted history sharing.',
    );
  }

  Future<bool> _run(
    Future<RoomEncryptionTrust> Function() action, {
    required String expectedRoomId,
    bool? expectedHistorySharingEnabled,
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      final next = await action();
      if (next.roomId != expectedRoomId ||
          (expectedHistorySharingEnabled != null &&
              next.historySharingEnabled != expectedHistorySharingEnabled)) {
        errorMessage.value = 'Kite received invalid encryption trust state.';
        return false;
      }
      state.value = next;
      return true;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  bool _isValidRoomId(String roomId) {
    return roomId.startsWith('!') &&
        roomId.contains(':') &&
        !roomId.contains(RegExp(r'\s'));
  }

  void dispose() {
    state.dispose();
    isBusy.dispose();
    errorMessage.dispose();
  }
}
