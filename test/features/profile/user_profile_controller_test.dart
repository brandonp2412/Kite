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
  Object? loadOwnError;
  Object? loadProfileError;
  Object? updateError;
  Object? dmError;
  Object? ignoreError;
  String? updatedDisplayName;
  Uri? updatedAvatar;
  bool avatarWasCleared = false;
  String? openedDmUserId;

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async {
    if (loadOwnError case final error?) throw error;
    return ownProfile;
  }

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async {
    if (loadProfileError case final error?) throw error;
    return profiles[userId]!;
  }

  @override
  Future<String> openDirectMessage(String userId) async {
    if (dmError case final error?) throw error;
    openedDmUserId = userId;
    return '!dm:example.org';
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

  test('loads another user profile and rejects malformed Matrix IDs', () async {
    final gateway = _FakeUserProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    await controller.loadUserProfile('@alice:example.org');
    expect(controller.viewedProfile.value?.displayName, 'Alice');

    await controller.loadUserProfile('alice');
    expect(controller.viewedProfile.value?.displayName, 'Alice');
    expect(controller.errorMessage.value, 'That Matrix user ID is not valid.');
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
}
