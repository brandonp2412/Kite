import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class _AuthApi implements MatrixNativeAuthSessionApi {
  @override
  Future<void> clearSession() async {}

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async => MatrixSdkAuthenticationDiscovery(
    homeserver: homeserver,
    methods: const <MatrixSdkAuthenticationMethod>{
      MatrixSdkAuthenticationMethod.password,
    },
  );

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async => MatrixSdkSessionDescriptor(
    userId: '@alice:${homeserver.host}',
    deviceId: 'DEVICE',
    homeserver: homeserver,
  );

  @override
  Future<void> logoutSession(MatrixSdkSessionDescriptor session) async {}

  @override
  Future<void> persistSession(MatrixSdkSessionDescriptor session) async {}

  @override
  Future<MatrixSdkSessionDescriptor?> restoreSession() async => null;
}

final class _ProfileApi implements MatrixNativeProfileApi {
  final ignored = <String>{'@spam:example.org'};
  final writes = <(String, bool)>[];

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<MatrixSdkUserProfile> loadOwnProfile() async =>
      const MatrixSdkUserProfile(userId: '@alice:example.org');

  @override
  Future<MatrixSdkUserProfile> loadProfile(String userId) async =>
      MatrixSdkUserProfile(userId: userId);

  @override
  Future<String> openDirectMessage(String userId) async => '!dm:example.org';

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {
    writes.add((userId, ignored));
    if (ignored) {
      this.ignored.add(userId);
    } else {
      this.ignored.remove(userId);
    }
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}
}

void main() {
  test(
    'native profile bridge exposes Matrix ignore state as block controls',
    () async {
      final profile = _ProfileApi();
      final boundary = NativeMatrixAccountSdkBoundary(
        _AuthApi(),
        profileApi: profile,
      );

      expect(
        boundary.accountCapabilities,
        contains(MatrixAccountSdkCapability.privacyControls),
      );
      expect(await boundary.loadBlockedUserIds(), <String>{
        '@spam:example.org',
      });

      await boundary.setUserBlocked(userId: '@bob:example.org', blocked: true);
      expect(profile.writes, <(String, bool)>[('@bob:example.org', true)]);
      expect(await boundary.loadIgnoredUserIds(), contains('@bob:example.org'));

      await boundary.setUserIgnored(
        userId: '@spam:example.org',
        ignored: false,
      );
      expect(profile.writes.last, ('@spam:example.org', false));
    },
  );

  test(
    'privacy controls remain unavailable without a production profile api',
    () {
      final boundary = NativeMatrixAccountSdkBoundary(_AuthApi());

      expect(
        boundary.accountCapabilities,
        isNot(contains(MatrixAccountSdkCapability.privacyControls)),
      );
      expect(
        boundary.loadBlockedUserIds(),
        throwsA(isA<MatrixSdkContractException>()),
      );
    },
  );
}
