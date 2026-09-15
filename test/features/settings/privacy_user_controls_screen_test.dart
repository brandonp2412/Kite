import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/settings/privacy_user_controls_screen.dart';

final class _PrivacyGateway implements UserProfileGateway {
  Set<String> ignored = <String>{'@ignored:example.org'};
  Set<String> blocked = <String>{'@blocked:example.org'};
  Object? loadFailure;
  Object? updateFailure;
  Completer<Set<String>>? deferredIgnored;
  Completer<Set<String>>? deferredBlocked;

  @override
  Future<Set<String>> loadIgnoredUserIds() async {
    if (loadFailure case final error?) throw error;
    final deferred = deferredIgnored;
    if (deferred != null) return deferred.future;
    return <String>{...ignored};
  }

  @override
  Future<Set<String>> loadBlockedUserIds() async {
    if (loadFailure case final error?) throw error;
    final deferred = deferredBlocked;
    if (deferred != null) return deferred.future;
    return <String>{...blocked};
  }

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {
    if (updateFailure case final error?) throw error;
    if (ignored) {
      this.ignored.add(userId);
    } else {
      this.ignored.remove(userId);
    }
  }

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {
    if (updateFailure case final error?) throw error;
    if (blocked) {
      this.blocked.add(userId);
    } else {
      this.blocked.remove(userId);
    }
  }

  @override
  Future<MatrixUserProfile> loadOwnProfile() => throw UnimplementedError();

  @override
  Future<MatrixUserProfile> loadProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<String> openDirectMessage(String userId) => throw UnimplementedError();

  @override
  Future<void> updateAvatar(Uri? avatarUri) => throw UnimplementedError();

  @override
  Future<void> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'lists privacy controls and removes them only after SDK success',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final gateway = _PrivacyGateway();
      final controller = UserProfileController(gateway);
      addTearDown(controller.dispose);
      await controller.refreshPrivacyControls();
      String? openedUser;

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyUserControlsScreen(
            controller: controller,
            loadOnInit: false,
            onOpenUser: (userId) => openedUser = userId,
          ),
        ),
      );

      expect(find.text('@ignored:example.org'), findsOneWidget);
      expect(find.text('@blocked:example.org'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('ignored-user-@ignored:example.org')),
      );
      expect(openedUser, '@ignored:example.org');

      await tester.tap(
        find.byKey(const Key('unignore-user-@ignored:example.org')),
      );
      await tester.pump();
      expect(controller.isIgnored('@ignored:example.org'), isFalse);
      expect(find.text('No ignored users'), findsOneWidget);

      gateway.updateFailure = StateError('access_token=secret');
      await tester.tap(
        find.byKey(const Key('unblock-user-@blocked:example.org')),
      );
      await tester.pump();
      expect(controller.isBlocked('@blocked:example.org'), isTrue);
      expect(find.text('Kite could not unblock that user.'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
    },
  );

  testWidgets('privacy refresh shows progress and disables stale actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final gateway = _PrivacyGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.refreshPrivacyControls();
    gateway.deferredIgnored = Completer<Set<String>>();
    gateway.deferredBlocked = Completer<Set<String>>();

    await tester.pumpWidget(
      MaterialApp(home: PrivacyUserControlsScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('unignore-user-@ignored:example.org')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('unblock-user-@blocked:example.org')),
          )
          .onPressed,
      isNull,
    );

    gateway.deferredIgnored!.complete(<String>{...gateway.ignored});
    gateway.deferredBlocked!.complete(<String>{...gateway.blocked});
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('unignore-user-@ignored:example.org')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('invalid gateway IDs never replace known privacy state', (
    tester,
  ) async {
    final gateway = _PrivacyGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.refreshPrivacyControls();
    gateway.ignored = <String>{'not-a-matrix-id'};

    await controller.refreshPrivacyControls();

    expect(controller.isIgnored('@ignored:example.org'), isTrue);
    expect(controller.ignoredUserIds.value, isNot(contains('not-a-matrix-id')));
    expect(
      controller.errorMessage.value,
      'Kite received invalid privacy settings.',
    );
  });
}
