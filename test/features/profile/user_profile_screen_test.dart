import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';

final class _FakeProfileGateway implements UserProfileGateway {
  MatrixUserProfile own = const MatrixUserProfile(
    userId: '@brandon:example.org',
    displayName: 'Brandon',
    avatarUri: null,
  );
  MatrixUserProfile other = const MatrixUserProfile(
    userId: '@alice:example.org',
    displayName: 'Alice',
  );
  Set<String> ignored = <String>{'@alice:example.org'};
  Set<String> blocked = <String>{};
  String? displayName;
  Uri? avatar;
  String? openedUserId;

  @override
  Future<Set<String>> loadBlockedUserIds() async => <String>{...blocked};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async => own;

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async => other;

  @override
  Future<String> openDirectMessage(String userId) async {
    openedUserId = userId;
    return '!dm:example.org';
  }

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {
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
    if (ignored) {
      this.ignored.add(userId);
    } else {
      this.ignored.remove(userId);
    }
  }

  @override
  Future<void> updateAvatar(Uri? avatarUri) async {
    avatar = avatarUri;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    this.displayName = displayName;
  }
}

void _useLargeView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('own profile edits display name and avatar through gateway', (
    tester,
  ) async {
    _useLargeView(tester);
    final gateway = _FakeProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();
    final selectedAvatar = Uri.parse('mxc://example.org/new-avatar');

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(
          controller: controller,
          loadOnInit: false,
          pickAvatar: () async => selectedAvatar,
        ),
      ),
    );

    expect(find.text('Brandon'), findsWidgets);
    expect(find.text('@brandon:example.org'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-display-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      'Brandon Dick',
    );
    await tester.tap(find.byKey(const Key('profile-save-display-name')));
    await tester.pumpAndSettle();

    expect(gateway.displayName, 'Brandon Dick');
    expect(controller.ownProfile.value?.displayName, 'Brandon Dick');
    expect(find.text('Brandon Dick'), findsWidgets);

    await tester.tap(find.byKey(const Key('edit-display-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('profile-save-display-name')));
    await tester.pumpAndSettle();

    expect(gateway.displayName, '');
    expect(controller.ownProfile.value?.displayName, '');
    expect(find.text('@brandon:example.org'), findsWidgets);

    await tester.tap(find.byKey(const Key('change-profile-avatar')));
    await tester.pump();
    expect(gateway.avatar, selectedAvatar);
    expect(controller.ownProfile.value?.avatarUri, selectedAvatar);
  });

  testWidgets('own profile paints cached fallback without a loader', (
    tester,
  ) async {
    _useLargeView(tester);
    final controller = UserProfileController(_FakeProfileGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(
          controller: controller,
          loadOnInit: false,
          fallbackProfile: const MatrixUserProfile(
            userId: '@brandon:example.org',
            displayName: 'Brandon cached',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Brandon cached'), findsWidgets);
    expect(find.text('@brandon:example.org'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'changing viewed user reloads without showing the previous profile',
    (tester) async {
      _useLargeView(tester);
      final gateway = _FakeProfileGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen.user(
            controller: controller,
            userId: '@alice:example.org',
            onOpenRoom: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);

      gateway.other = const MatrixUserProfile(
        userId: '@bob:example.org',
        displayName: 'Bob',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen.user(
            controller: controller,
            userId: '@bob:example.org',
            onOpenRoom: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.viewedProfile.value?.userId, '@bob:example.org');
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    },
  );

  testWidgets(
    'viewed profile keeps messaging available while privacy state loads',
    (tester) async {
      _useLargeView(tester);
      final gateway = _FakeProfileGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);
      controller.viewedProfile.value = gateway.other;
      controller.isPrivacyLoading.value = true;
      controller.hasPrivacyState.value = false;
      String? openedRoomId;

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen.user(
            controller: controller,
            userId: '@alice:example.org',
            loadOnInit: false,
            onOpenRoom: (roomId) => openedRoomId = roomId,
          ),
        ),
      );

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profile-message')))
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('profile-ignore')), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('profile-block')))
            .onChanged,
        isNull,
      );

      await tester.tap(find.byKey(const Key('profile-message')));
      await tester.pump();
      expect(openedRoomId, '!dm:example.org');

      controller.isPrivacyLoading.value = false;
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('profile-block')))
            .onChanged,
        isNull,
      );

      controller.hasPrivacyState.value = true;
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('profile-block')))
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets('viewed profile loads privacy state and opens a DM', (
    tester,
  ) async {
    _useLargeView(tester);
    final gateway = _FakeProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadUserProfile('@alice:example.org');
    String? openedRoomId;

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.user(
          controller: controller,
          userId: '@alice:example.org',
          loadOnInit: false,
          onOpenRoom: (roomId) => openedRoomId = roomId,
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('@alice:example.org'), findsOneWidget);
    expect(find.byKey(const Key('profile-ignore')), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('profile-block')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('profile-message')));
    await tester.pump();
    expect(gateway.openedUserId, '@alice:example.org');
    expect(openedRoomId, '!dm:example.org');

    await tester.tap(find.byKey(const Key('profile-block')));
    await tester.pump();
    expect(controller.isBlocked('@alice:example.org'), isTrue);
  });
}
