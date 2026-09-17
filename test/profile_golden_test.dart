import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';

final class _GoldenProfileGateway implements UserProfileGateway {
  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{
    '@alice:example.org',
  };

  @override
  Future<MatrixUserProfile> loadOwnProfile() async => const MatrixUserProfile(
    userId: '@kite:example.org',
    displayName: 'Kite User',
    avatarUri: null,
  );

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async =>
      const MatrixUserProfile(
        userId: '@alice:example.org',
        displayName: 'Alice Example',
        avatarUri: null,
      );

  @override
  Future<String> openDirectMessage(String userId) async =>
      '!profile-golden:example.org';

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {}

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {}

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}
}

Future<void> _configurePhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app({required ThemeMode themeMode, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: KiteTheme.light,
    darkTheme: KiteTheme.dark,
    themeMode: themeMode,
    home: home,
  );
}

void main() {
  for (final variant in <(String, ThemeMode)>[
    ('light', ThemeMode.light),
    ('dark', ThemeMode.dark),
  ]) {
    testWidgets('approved own profile baseline - ${variant.$1}', (
      tester,
    ) async {
      await _configurePhone(tester);
      final controller = UserProfileController(_GoldenProfileGateway());
      addTearDown(controller.dispose);
      await controller.loadOwnProfile();

      await tester.pumpWidget(
        _app(
          themeMode: variant.$2,
          home: UserProfileScreen.own(
            controller: controller,
            loadOnInit: false,
            pickAvatar: () async => Uri.parse('mxc://example.org/new-avatar'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kite User'), findsWidgets);
      expect(find.byKey(const Key('edit-display-name')), findsOneWidget);
      expect(find.byKey(const Key('change-profile-avatar')), findsOneWidget);

      await expectLater(
        find.byType(UserProfileScreen),
        matchesGoldenFile('goldens/profile_own_${variant.$1}.png'),
      );
    });

    testWidgets('approved other-user profile baseline - ${variant.$1}', (
      tester,
    ) async {
      await _configurePhone(tester);
      final controller = UserProfileController(_GoldenProfileGateway());
      addTearDown(controller.dispose);
      await controller.loadUserProfile('@alice:example.org');

      await tester.pumpWidget(
        _app(
          themeMode: variant.$2,
          home: UserProfileScreen.user(
            controller: controller,
            userId: '@alice:example.org',
            onOpenRoom: (_) {},
            loadOnInit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice Example'), findsOneWidget);
      expect(find.byKey(const Key('profile-message')), findsOneWidget);
      expect(find.byKey(const Key('profile-ignore')), findsNothing);
      expect(find.byKey(const Key('profile-block')), findsOneWidget);

      await expectLater(
        find.byType(UserProfileScreen),
        matchesGoldenFile('goldens/profile_other_${variant.$1}.png'),
      );
    });
  }
}
