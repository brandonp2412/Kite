import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/encryption_trust_controller.dart';

final class _FakeEncryptionTrustGateway implements EncryptionTrustGateway {
  RoomEncryptionTrust current = RoomEncryptionTrust(
    roomId: '!room:example.org',
    isEncrypted: true,
    trustState: EncryptionTrustState.unverifiedDevice,
    historySharingSupported: true,
    historySharingEnabled: false,
  );
  Object? failure;
  bool ignoreHistorySharingUpdate = false;
  String? loadedRoomId;
  (String, bool)? historySharingUpdate;
  Completer<RoomEncryptionTrust>? deferredLoad;

  @override
  Future<RoomEncryptionTrust> loadRoomTrust(String roomId) async {
    if (failure case final error?) throw error;
    loadedRoomId = roomId;
    final deferred = deferredLoad;
    if (deferred != null) return deferred.future;
    return current;
  }

  @override
  Future<RoomEncryptionTrust> setHistorySharing({
    required String roomId,
    required bool enabled,
  }) async {
    if (failure case final error?) throw error;
    historySharingUpdate = (roomId, enabled);
    if (!ignoreHistorySharingUpdate) {
      current = current.copyWith(historySharingEnabled: enabled);
    }
    return current;
  }
}

void main() {
  test('room trust rejects malformed or impossible SDK metadata', () {
    expect(
      () => RoomEncryptionTrust(
        roomId: ' !room:example.org ',
        isEncrypted: true,
        trustState: EncryptionTrustState.verified,
        historySharingSupported: true,
        historySharingEnabled: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: false,
        trustState: EncryptionTrustState.unknown,
        historySharingSupported: true,
        historySharingEnabled: false,
      ),
      throwsArgumentError,
    );
  });

  test('account change reset clears room encryption state', () async {
    final gateway = _FakeEncryptionTrustGateway();
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isTrue);
    expect(controller.state.value, isNotNull);

    expect(controller.resetForAccountChange(), isTrue);
    expect(controller.state.value, isNull);
    expect(controller.warningMessage, isNull);
    expect(controller.errorMessage.value, isNull);
  });

  test('account reset invalidates an in-flight room trust load', () async {
    final deferred = Completer<RoomEncryptionTrust>();
    final gateway = _FakeEncryptionTrustGateway()..deferredLoad = deferred;
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    final loading = controller.load('!room:example.org');
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBusy.value, isTrue);

    expect(controller.resetForAccountChange(), isTrue);
    expect(controller.isBusy.value, isFalse);
    deferred.complete(gateway.current);
    expect(await loading, isFalse);

    expect(controller.state.value, isNull);
    expect(controller.warningMessage, isNull);
  });

  test('loads SDK-owned encryption and device trust state', () async {
    final gateway = _FakeEncryptionTrustGateway();
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load(' !room:example.org '), isTrue);
    expect(gateway.loadedRoomId, '!room:example.org');
    expect(controller.state.value?.isEncrypted, isTrue);
    expect(
      controller.state.value?.trustState,
      EncryptionTrustState.unverifiedDevice,
    );
    expect(controller.state.value?.requiresTrustWarning, isTrue);
    expect(
      controller.warningMessage,
      'This encrypted room includes an unverified device.',
    );
  });

  test('distinguishes unverified users from verified room state', () async {
    final gateway = _FakeEncryptionTrustGateway()
      ..current = RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: true,
        trustState: EncryptionTrustState.unverifiedUser,
        historySharingSupported: false,
        historySharingEnabled: false,
      );
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isTrue);
    expect(
      controller.warningMessage,
      'This encrypted room includes an unverified user.',
    );

    gateway.current = RoomEncryptionTrust(
      roomId: '!room:example.org',
      isEncrypted: true,
      trustState: EncryptionTrustState.verified,
      historySharingSupported: false,
      historySharingEnabled: false,
    );
    expect(await controller.load('!room:example.org'), isTrue);
    expect(controller.warningMessage, isNull);
    expect(controller.state.value?.requiresTrustWarning, isFalse);
  });

  test('unknown encrypted trust requires a visible warning', () async {
    final gateway = _FakeEncryptionTrustGateway()
      ..current = RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: true,
        trustState: EncryptionTrustState.unknown,
        historySharingSupported: false,
        historySharingEnabled: false,
      );
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isTrue);
    expect(controller.state.value?.requiresTrustWarning, isTrue);
    expect(
      controller.warningMessage,
      'This encrypted room has unknown verification state.',
    );

    gateway.current = RoomEncryptionTrust(
      roomId: '!plain:example.org',
      isEncrypted: false,
      trustState: EncryptionTrustState.unknown,
      historySharingSupported: false,
      historySharingEnabled: false,
    );
    expect(await controller.load('!plain:example.org'), isTrue);
    expect(controller.state.value?.requiresTrustWarning, isFalse);
    expect(controller.warningMessage, isNull);
  });

  test(
    'history sharing is delegated only when SDK policy supports it',
    () async {
      final gateway = _FakeEncryptionTrustGateway();
      final controller = EncryptionTrustController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.load('!room:example.org'), isTrue);
      expect(await controller.setHistorySharing(true), isTrue);
      expect(gateway.historySharingUpdate, ('!room:example.org', true));
      expect(controller.state.value?.historySharingEnabled, isTrue);

      gateway.current = RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: true,
        trustState: EncryptionTrustState.verified,
        historySharingSupported: false,
        historySharingEnabled: false,
      );
      expect(await controller.load('!room:example.org'), isTrue);
      gateway.historySharingUpdate = null;

      expect(await controller.setHistorySharing(true), isFalse);
      expect(gateway.historySharingUpdate, isNull);
      expect(
        controller.errorMessage.value,
        'Encrypted history sharing is not supported in this room.',
      );
    },
  );

  test(
    'history sharing rejects SDK state that loses encrypted support',
    () async {
      final gateway = _FakeEncryptionTrustGateway();
      final controller = EncryptionTrustController(gateway);
      addTearDown(controller.dispose);
      expect(await controller.load('!room:example.org'), isTrue);

      gateway.current = RoomEncryptionTrust(
        roomId: '!room:example.org',
        isEncrypted: true,
        trustState: EncryptionTrustState.verified,
        historySharingSupported: false,
        historySharingEnabled: false,
      );
      gateway.ignoreHistorySharingUpdate = true;

      expect(await controller.setHistorySharing(false), isFalse);
      expect(
        controller.errorMessage.value,
        'Kite received invalid encryption trust state.',
      );
    },
  );

  test(
    'history sharing rejects SDK state that did not apply the request',
    () async {
      final gateway = _FakeEncryptionTrustGateway()
        ..ignoreHistorySharingUpdate = true;
      final controller = EncryptionTrustController(gateway);
      addTearDown(controller.dispose);
      expect(await controller.load('!room:example.org'), isTrue);

      expect(await controller.setHistorySharing(true), isFalse);
      expect(gateway.historySharingUpdate, ('!room:example.org', true));
      expect(controller.state.value?.historySharingEnabled, isFalse);
      expect(
        controller.errorMessage.value,
        'Kite received invalid encryption trust state.',
      );
    },
  );

  test('invalid room IDs never reach the trust gateway', () async {
    final gateway = _FakeEncryptionTrustGateway();
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('room-without-sigil'), isFalse);
    expect(gateway.loadedRoomId, isNull);
    expect(controller.errorMessage.value, 'Choose a valid Matrix room.');

    expect(await controller.load('!:'), isFalse);
    expect(gateway.loadedRoomId, isNull);
    expect(controller.errorMessage.value, 'Choose a valid Matrix room.');
  });

  test('mismatched SDK state is rejected', () async {
    final gateway = _FakeEncryptionTrustGateway()
      ..current = RoomEncryptionTrust(
        roomId: '!different:example.org',
        isEncrypted: true,
        trustState: EncryptionTrustState.verified,
        historySharingSupported: true,
        historySharingEnabled: false,
      );
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isFalse);
    expect(controller.state.value, isNull);
    expect(
      controller.errorMessage.value,
      'Kite received invalid encryption trust state.',
    );
  });

  test('failed room switch clears stale encryption trust state', () async {
    final gateway = _FakeEncryptionTrustGateway();
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isTrue);
    expect(controller.state.value, isNotNull);

    gateway.failure = StateError('decrypted_message=secret');
    expect(await controller.load('!next:example.org'), isFalse);

    expect(controller.state.value, isNull);
    expect(controller.warningMessage, isNull);
    expect(
      controller.errorMessage.value,
      'Kite could not read encryption trust state.',
    );
  });

  test('invalid room selection clears stale encryption trust state', () async {
    final gateway = _FakeEncryptionTrustGateway();
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isTrue);
    expect(await controller.load('room-without-sigil'), isFalse);

    expect(controller.state.value, isNull);
    expect(controller.warningMessage, isNull);
  });

  test('gateway failures expose fixed public errors only', () async {
    final gateway = _FakeEncryptionTrustGateway()
      ..failure = StateError(
        'access_token=token decrypted_message=secret recovery_key=hidden',
      );
    final controller = EncryptionTrustController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load('!room:example.org'), isFalse);
    expect(
      controller.errorMessage.value,
      'Kite could not read encryption trust state.',
    );
    expect(controller.errorMessage.value, isNot(contains('token')));
    expect(controller.errorMessage.value, isNot(contains('secret')));
    expect(controller.errorMessage.value, isNot(contains('recovery_key')));
  });
}
