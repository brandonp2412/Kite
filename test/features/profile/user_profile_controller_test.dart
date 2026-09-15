import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/profile/user_profile_controller.dart';

final class _FakeUserProfileGateway implements UserProfileGateway {
  MatrixUserProfile ownProfile = const MatrixUserProfile(
    userId: '@brandon:example.org',
    displayName: 'Brandon',
  );
  final profiles = <String, MatrixUserProfile>{
    '@alice:example.org': const MatrixUserProfile(
      userId: '@alice:example.org',
      displayName: 'Alice',
    ),
  };
  Set<String> ignored = <String>{};
  Set<String> blocked = <String>{};
  Object? loadOwnError;
  Object? loadProfileError;
  Object? updateError;
  Object? dmError;
  Object? ignoreError;
  Object? blockError;
  String dmRoomId = '!dm:example.org';
  String? updatedDisplayName;
  Uri? updatedAvatar;
  bool avatarWasCleared = false;
  String? openedDmUserId;
  Completer<MatrixUserProfile>? deferredOwnProfile;
  Completer<MatrixUserProfile>? deferredViewedProfile;

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<Set<String>> loadBlockedUserIds() async => <String>{...blocked};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async {
    if (loadOwnError case final error?) throw error;
    final deferred = deferredOwnProfile;
    if (deferred != null) return deferred.future;
    return ownProfile;
  }

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async {
    if (loadProfileError case final error?) throw error;
    final deferred = deferredViewedProfile;
    if (deferred != null) return deferred.future;
    return profiles[userId]!;
  }

  @override
  Future<String> openDirectMessage(String userId) async {
    if (dmError case final error?) throw error;
    openedDmUserId = userId;
    return dmRoomId;
  }

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {
    if (blockError case final error?) throw error;
    if (blocked) {
      this.blocked.add(userId);
    } else {
      this.blocked.remove(userId);
    }
  }

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {
    if (ignoreError case final error?) throw error;
    if (ignored) {
      this.ignored.add(userId);
    } else {
      this.ignored.remove(userId);
    }
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {
    if (updateError case final error?) throw error;
    updatedAvatar = avatarUri;
    avatarWasCleared = avatarUri == null;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    if (updateError case final error?) throw error;
    updatedDisplayName = displayName;
  }
}

void main() {
  test(
    'loads own profile and ignored users without clearing known state',
    () async {
      final gateway = _FakeUserProfileGateway()
        ..ignored = {'@spam:example.org'};
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      await controller.loadOwnProfile();

      expect(controller.ownProfile.value?.displayName, 'Brandon');
      expect(controller.isIgnored('@spam:example.org'), isTrue);

      gateway.loadOwnError = StateError('access_token=secret');
      await controller.loadOwnProfile();

      expect(controller.ownProfile.value?.displayName, 'Brandon');
      expect(
        controller.errorMessage.value,
        'Kite could not load your profile.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test('account change reset clears profile and privacy state', () async {
    final gateway = _FakeUserProfileGateway()
      ..ignored = {'@ignored:example.org'}
      ..blocked = {'@blocked:example.org'};
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    await controller.loadOwnProfile();
    await controller.loadUserProfile('@alice:example.org');
    expect(controller.ownProfile.value, isNotNull);
    expect(controller.viewedProfile.value, isNotNull);
    expect(controller.ignoredUserIds.value, isNotEmpty);
    expect(controller.blockedUserIds.value, isNotEmpty);

    expect(controller.resetForAccountChange(), isTrue);

    expect(controller.ownProfile.value, isNull);
    expect(controller.viewedProfile.value, isNull);
    expect(controller.ignoredUserIds.value, isEmpty);
    expect(controller.blockedUserIds.value, isEmpty);
    expect(controller.errorMessage.value, isNull);
  });

  test('account change reset cannot race an in-flight profile load', () async {
    final gateway = _FakeUserProfileGateway()
      ..deferredOwnProfile = Completer<MatrixUserProfile>();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    final loading = controller.loadOwnProfile();
    await Future<void>.delayed(Duration.zero);

    expect(controller.resetForAccountChange(), isFalse);
    expect(controller.isLoading.value, isTrue);

    gateway.deferredOwnProfile!.complete(gateway.ownProfile);
    await loading;
    expect(controller.ownProfile.value?.userId, '@brandon:example.org');
  });

  test('loads another user profile and rejects malformed Matrix IDs', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    await controller.loadUserProfile('@alice:example.org');
    expect(controller.viewedProfile.value?.displayName, 'Alice');

    await controller.loadUserProfile('alice');
    expect(controller.viewedProfile.value, isNull);
    expect(controller.errorMessage.value, 'That Matrix user ID is not valid.');
  });

  test(
    'loading a different profile clears stale user data immediately',
    () async {
      final gateway = _FakeUserProfileGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);
      await controller.loadUserProfile('@alice:example.org');
      expect(controller.viewedProfile.value?.displayName, 'Alice');

      final deferred = Completer<MatrixUserProfile>();
      gateway.deferredViewedProfile = deferred;
      final loading = controller.loadUserProfile('@bob:example.org');
      await Future<void>.delayed(Duration.zero);

      expect(controller.isLoading.value, isTrue);
      expect(controller.viewedProfile.value, isNull);

      deferred.complete(
        const MatrixUserProfile(userId: '@bob:example.org', displayName: 'Bob'),
      );
      await loading;
      expect(controller.viewedProfile.value?.displayName, 'Bob');
    },
  );

  test(
    'rejects profile and privacy data that does not match Matrix identity',
    () async {
      final gateway = _FakeUserProfileGateway()
        ..profiles['@alice:example.org'] = const MatrixUserProfile(
          userId: '@mallory:example.org',
          displayName: 'Mallory',
        );
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      await controller.loadUserProfile('@alice:example.org');

      expect(controller.viewedProfile.value, isNull);
      expect(
        controller.errorMessage.value,
        'Kite received invalid profile data.',
      );

      gateway.ownProfile = const MatrixUserProfile(
        userId: '@brandon:example.org',
        displayName: 'Brandon',
      );
      gateway.ignored = {' invalid-user '};
      await controller.loadOwnProfile();

      expect(controller.ownProfile.value, isNull);
      expect(controller.ignoredUserIds.value, isEmpty);
      expect(
        controller.errorMessage.value,
        'Kite received invalid profile data.',
      );
    },
  );

  test('rejects whitespace-normalized Matrix IDs before gateway use', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    await controller.loadUserProfile(' @alice:example.org ');

    expect(controller.viewedProfile.value, isNull);
    expect(controller.errorMessage.value, 'That Matrix user ID is not valid.');
  });

  test('profile mutation cannot race an in-flight profile refresh', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    gateway.deferredOwnProfile = Completer<MatrixUserProfile>();
    final refresh = controller.loadOwnProfile();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isLoading.value, isTrue);

    expect(await controller.updateDisplayName('Racing update'), isFalse);
    expect(gateway.updatedDisplayName, isNull);

    gateway.deferredOwnProfile!.complete(gateway.ownProfile);
    await refresh;
    expect(controller.isLoading.value, isFalse);
  });

  test('updates display name and avatar only after gateway success', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    expect(await controller.updateDisplayName('  Brandon Dick  '), isTrue);
    expect(gateway.updatedDisplayName, 'Brandon Dick');
    expect(controller.ownProfile.value?.displayName, 'Brandon Dick');

    final avatar = Uri.parse('mxc://example.org/avatar');
    expect(await controller.updateAvatar(avatar), isTrue);
    expect(gateway.updatedAvatar, avatar);
    expect(controller.ownProfile.value?.avatarUri, avatar);

    expect(await controller.updateAvatar(null), isTrue);
    expect(gateway.avatarWasCleared, isTrue);
    expect(controller.ownProfile.value?.avatarUri, isNull);
  });

  test(
    'opens a DM through the gateway without leaking gateway failures',
    () async {
      final gateway = _FakeUserProfileGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.openDirectMessage('@alice:example.org'),
        '!dm:example.org',
      );
      expect(gateway.openedDmUserId, '@alice:example.org');

      gateway.dmError = StateError('access_token=secret');
      expect(await controller.openDirectMessage('@alice:example.org'), isNull);
      expect(
        controller.errorMessage.value,
        'Kite could not open a direct message.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));

      gateway.dmError = null;
      gateway.dmRoomId = 'not-a-room';
      expect(await controller.openDirectMessage('@alice:example.org'), isNull);
      expect(
        controller.errorMessage.value,
        'Kite received an invalid direct-message room.',
      );
    },
  );

  test(
    'ignore state changes only after a successful Matrix gateway update',
    () async {
      final gateway = _FakeUserProfileGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);
      await controller.loadOwnProfile();

      expect(await controller.setIgnored('@alice:example.org', true), isTrue);
      expect(controller.isIgnored('@alice:example.org'), isTrue);

      gateway.ignoreError = StateError('recovery_key=secret');
      expect(await controller.setIgnored('@alice:example.org', false), isFalse);
      expect(controller.isIgnored('@alice:example.org'), isTrue);
      expect(
        controller.errorMessage.value,
        'Kite could not stop ignoring that user.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'block state changes only after a successful Matrix gateway update',
    () async {
      final gateway = _FakeUserProfileGateway()
        ..blocked = {'@spam:example.org'};
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);
      await controller.loadOwnProfile();

      expect(controller.isBlocked('@spam:example.org'), isTrue);
      expect(await controller.setBlocked('@alice:example.org', true), isTrue);
      expect(controller.isBlocked('@alice:example.org'), isTrue);

      gateway.blockError = StateError('access_token=secret');
      expect(await controller.setBlocked('@alice:example.org', false), isFalse);
      expect(controller.isBlocked('@alice:example.org'), isTrue);
      expect(
        controller.errorMessage.value,
        'Kite could not unblock that user.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );
}
