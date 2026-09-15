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
  Object? loadIgnoredError;
  Object? loadBlockedError;
  String dmRoomId = '!dm:example.org';
  String? updatedDisplayName;
  Uri? updatedAvatar;
  bool avatarWasCleared = false;
  String? openedDmUserId;
  Completer<MatrixUserProfile>? deferredOwnProfile;
  Completer<MatrixUserProfile>? deferredViewedProfile;
  Completer<Set<String>>? deferredIgnored;
  Completer<Set<String>>? deferredBlocked;

  @override
  Future<Set<String>> loadIgnoredUserIds() async {
    if (loadIgnoredError case final error?) throw error;
    final deferred = deferredIgnored;
    if (deferred != null) return deferred.future;
    return <String>{...ignored};
  }

  @override
  Future<Set<String>> loadBlockedUserIds() async {
    if (loadBlockedError case final error?) throw error;
    final deferred = deferredBlocked;
    if (deferred != null) return deferred.future;
    return <String>{...blocked};
  }

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
    'loads own profile without waiting on unrelated privacy state',
    () async {
      final gateway = _FakeUserProfileGateway()
        ..ignored = {'@spam:example.org'}
        ..loadIgnoredError = StateError('access_token=secret')
        ..loadBlockedError = StateError('recovery_key=secret');
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      await controller.loadOwnProfile();

      expect(controller.ownProfile.value?.displayName, 'Brandon');
      expect(controller.hasPrivacyState.value, isFalse);
      expect(controller.isIgnored('@spam:example.org'), isFalse);
      expect(controller.errorMessage.value, isNull);

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

  test('account change reset invalidates an in-flight profile load', () async {
    final gateway = _FakeUserProfileGateway()
      ..deferredOwnProfile = Completer<MatrixUserProfile>();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    final loading = controller.loadOwnProfile();
    await Future<void>.delayed(Duration.zero);

    expect(controller.resetForAccountChange(), isTrue);
    expect(controller.isLoading.value, isFalse);
    expect(controller.ownProfile.value, isNull);

    gateway.deferredOwnProfile!.complete(gateway.ownProfile);
    await loading;
    expect(controller.ownProfile.value, isNull);
    expect(controller.errorMessage.value, isNull);
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
    'publishes viewed profile before privacy controls finish loading',
    () async {
      final ignored = Completer<Set<String>>();
      final blocked = Completer<Set<String>>();
      final gateway = _FakeUserProfileGateway()
        ..deferredIgnored = ignored
        ..deferredBlocked = blocked;
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      final loading = controller.loadUserProfile('@alice:example.org');
      await Future<void>.delayed(Duration.zero);

      expect(controller.viewedProfile.value?.displayName, 'Alice');
      expect(controller.isLoading.value, isFalse);
      expect(controller.isPrivacyLoading.value, isTrue);
      expect(
        await controller.openDirectMessage('@alice:example.org'),
        '!dm:example.org',
      );
      expect(await controller.setIgnored('@alice:example.org', true), isFalse);
      expect(controller.isIgnored('@alice:example.org'), isFalse);

      ignored.complete(<String>{'@alice:example.org'});
      blocked.complete(<String>{});
      await loading;

      expect(controller.isPrivacyLoading.value, isFalse);
      expect(controller.hasPrivacyState.value, isTrue);
      expect(controller.isIgnored('@alice:example.org'), isTrue);
    },
  );

  test('same-user refresh preserves the last known profile offline', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadUserProfile('@alice:example.org');
    final knownProfile = controller.viewedProfile.value;

    gateway.loadProfileError = StateError('network unavailable');
    await controller.loadUserProfile('@alice:example.org');

    expect(controller.viewedProfile.value, same(knownProfile));
    expect(controller.errorMessage.value, 'Kite could not load that profile.');
  });

  test(
    'invalid profile target also invalidates an in-flight previous user',
    () async {
      final first = Completer<MatrixUserProfile>();
      final gateway = _FakeUserProfileGateway()..deferredViewedProfile = first;
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      final aliceLoad = controller.loadUserProfile('@alice:example.org');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading.value, isTrue);

      await controller.loadUserProfile('not-a-matrix-id');
      expect(controller.isLoading.value, isFalse);
      expect(controller.viewedProfile.value, isNull);
      expect(
        controller.errorMessage.value,
        'That Matrix user ID is not valid.',
      );

      first.complete(
        const MatrixUserProfile(
          userId: '@alice:example.org',
          displayName: 'Alice',
        ),
      );
      await aliceLoad;

      expect(controller.viewedProfile.value, isNull);
      expect(
        controller.errorMessage.value,
        'That Matrix user ID is not valid.',
      );
    },
  );

  test('new profile request supersedes an in-flight previous user', () async {
    final first = Completer<MatrixUserProfile>();
    final second = Completer<MatrixUserProfile>();
    final gateway = _FakeUserProfileGateway()..deferredViewedProfile = first;
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    final aliceLoad = controller.loadUserProfile('@alice:example.org');
    await Future<void>.delayed(Duration.zero);
    gateway.deferredViewedProfile = second;
    final bobLoad = controller.loadUserProfile('@bob:example.org');
    await Future<void>.delayed(Duration.zero);

    second.complete(
      const MatrixUserProfile(userId: '@bob:example.org', displayName: 'Bob'),
    );
    await bobLoad;
    expect(controller.viewedProfile.value?.userId, '@bob:example.org');
    expect(controller.isLoading.value, isFalse);

    first.complete(
      const MatrixUserProfile(
        userId: '@alice:example.org',
        displayName: 'Alice',
      ),
    );
    await aliceLoad;

    expect(controller.viewedProfile.value?.userId, '@bob:example.org');
    expect(controller.viewedProfile.value?.displayName, 'Bob');
    expect(controller.errorMessage.value, isNull);
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

      gateway.profiles['@alice:example.org'] = const MatrixUserProfile(
        userId: '@alice:example.org',
        displayName: 'Alice',
      );
      gateway.ignored = {' invalid-user '};
      await controller.loadUserProfile('@alice:example.org');

      expect(controller.viewedProfile.value?.userId, '@alice:example.org');
      expect(controller.ignoredUserIds.value, isEmpty);
      expect(
        controller.errorMessage.value,
        'Kite received invalid privacy settings.',
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

  test('privacy refresh failure does not blank a valid profile', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    gateway.loadIgnoredError = StateError('access_token=secret');
    await controller.loadOwnProfile();

    expect(controller.ownProfile.value?.displayName, 'Brandon');
    expect(controller.errorMessage.value, isNull);

    gateway.loadBlockedError = StateError('recovery_key=secret');
    await controller.loadUserProfile('@alice:example.org');

    expect(controller.viewedProfile.value?.displayName, 'Alice');
    expect(controller.hasPrivacyState.value, isFalse);
    expect(
      controller.errorMessage.value,
      'Kite could not load your privacy settings.',
    );
    expect(controller.errorMessage.value, isNot(contains('secret')));
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

  test('rejects non-MXC avatar data before it reaches the gateway', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    expect(
      await controller.updateAvatar(
        Uri.parse('file:///tmp/private-avatar.jpg'),
      ),
      isFalse,
    );
    expect(gateway.updatedAvatar, isNull);
    expect(
      controller.errorMessage.value,
      'Kite received an invalid Matrix avatar.',
    );

    gateway.ownProfile = MatrixUserProfile(
      userId: '@brandon:example.org',
      avatarUri: Uri.parse('https://example.org/avatar.jpg'),
    );
    await controller.loadOwnProfile();
    expect(
      controller.errorMessage.value,
      'Kite received invalid profile data.',
    );
  });

  test('updates display name and avatar only after gateway success', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    expect(await controller.updateDisplayName('  Brandon Dick  '), isTrue);
    expect(gateway.updatedDisplayName, 'Brandon Dick');
    expect(controller.ownProfile.value?.displayName, 'Brandon Dick');

    expect(await controller.updateDisplayName('   '), isTrue);
    expect(gateway.updatedDisplayName, '');
    expect(controller.ownProfile.value?.displayName, '');

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
      await controller.refreshPrivacyControls();

      expect(controller.hasPrivacyState.value, isTrue);
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
      await controller.loadUserProfile('@alice:example.org');

      expect(controller.hasPrivacyState.value, isTrue);
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
