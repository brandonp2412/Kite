import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';
import 'package:kite/testing/deterministic_adapters.dart';

final class _DeferredProfileGateway implements UserProfileGateway {
  final blockWrite = Completer<void>();
  MatrixUserProfile ownProfile = const MatrixUserProfile(
    userId: '@brandon:example.org',
  );
  Completer<MatrixUserProfile>? ownProfileLoad;

  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => const <String>{};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async {
    final deferred = ownProfileLoad;
    if (deferred != null) return deferred.future;
    return ownProfile;
  }

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async =>
      const MatrixUserProfile(
        userId: '@alice:example.org',
        displayName: 'Alice',
      );

  @override
  Future<String> openDirectMessage(String userId) async => '!dm:example.org';

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) => blockWrite.future;

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

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('profile load reserves final geometry at 120 Hz', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredProfileGateway()
      ..ownProfileLoad = Completer<MatrixUserProfile>();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(
          controller: controller,
          pickAvatar: () async => null,
        ),
      ),
    );
    await tester.pump();

    final content = find.byKey(const Key('profile-content-slot'));
    final status = find.byKey(const Key('profile-status-slot'));
    final initialContent = _rectOf(tester, content);
    final initialStatus = _rectOf(tester, status);
    expect(find.text('Loading profile…'), findsOneWidget);

    gateway.ownProfileLoad!.complete(
      MatrixUserProfile(
        userId: '@brandon:example.org',
        displayName: 'Brandon',
        avatarUri: Uri.parse('mxc://example.org/avatar'),
      ),
    );
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, content), initialContent);
      expect(_rectOf(tester, status), initialStatus);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    expect(find.text('Brandon'), findsWidgets);
    expect(find.byKey(const Key('remove-profile-avatar')), findsOneWidget);
    expect(_rectOf(tester, content), initialContent);
    expect(_rectOf(tester, status), initialStatus);
  });

  testWidgets('display-name editor keeps profile geometry stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(controller: controller, loadOnInit: false),
      ),
    );

    final list = find.byKey(const Key('user-profile-list'));
    final header = find.byKey(const Key('profile-header'));
    final initialList = _rectOf(tester, list);
    final initialHeader = _rectOf(tester, header);

    await tester.tap(find.byKey(const Key('edit-display-name')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, header), initialHeader);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('profile-display-name-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(_rectOf(tester, list), initialList);
    expect(_rectOf(tester, header), initialHeader);
  });

  testWidgets('privacy mutation keeps profile geometry stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadUserProfile('@alice:example.org');

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.user(
          controller: controller,
          userId: '@alice:example.org',
          onOpenRoom: (_) {},
          loadOnInit: false,
        ),
      ),
    );

    final list = find.byKey(const Key('user-profile-list'));
    final header = find.byKey(const Key('profile-header'));
    final status = find.byKey(const Key('profile-status-slot'));
    final initialList = _rectOf(tester, list);
    final initialHeader = _rectOf(tester, header);
    final initialStatus = _rectOf(tester, status);

    await tester.tap(find.byKey(const Key('profile-block')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, header), initialHeader);
      expect(_rectOf(tester, status), initialStatus);
      expect(tester.takeException(), isNull);
    }

    gateway.blockWrite.complete();
    await tester.pump();
    expect(_rectOf(tester, header), initialHeader);
    expect(_rectOf(tester, status), initialStatus);
    expect(controller.isBlocked('@alice:example.org'), isTrue);
  });
  testWidgets('avatar preview viewer stays stable at 120 Hz', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final gateway = _DeferredProfileGateway()
      ..ownProfile = MatrixUserProfile(
        userId: '@brandon:example.org',
        displayName: 'Brandon',
        avatarUri: Uri.parse('mxc://example.org/avatar'),
      );
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(
          controller: controller,
          loadOnInit: false,
          avatarImageProvider: (_, {dimension}) =>
              MemoryImage(DeterministicImageFixtures.transparentPng1x1),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('profile-avatar-preview')));
    await tester.pumpAndSettle();
    final viewer = find.byKey(const Key('media-viewer'));
    final pageView = find.byKey(const Key('media-page-view'));
    expect(viewer, findsOneWidget);
    expect(pageView, findsOneWidget);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final initialViewer = _rectOf(tester, viewer);
    final initialPageView = _rectOf(tester, pageView);
    await tester.tap(find.byKey(const Key('media-gesture-surface')));

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, viewer), initialViewer);
      expect(_rectOf(tester, pageView), initialPageView);
      expect(tester.takeException(), isNull);
    }
  });
}
