import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';

final class _DeferredProfileGateway implements UserProfileGateway {
  final ignoreWrite = Completer<void>();

  @override
  Future<Set<String>> loadBlockedUserIds() async => const <String>{};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => const <String>{};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async =>
      const MatrixUserProfile(userId: '@brandon:example.org');

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
  }) async {}

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) => ignoreWrite.future;

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

    await tester.tap(find.byKey(const Key('profile-ignore')));
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, header), initialHeader);
      expect(_rectOf(tester, status), initialStatus);
      expect(tester.takeException(), isNull);
    }

    gateway.ignoreWrite.complete();
    await tester.pump();
    expect(_rectOf(tester, header), initialHeader);
    expect(_rectOf(tester, status), initialStatus);
    expect(controller.isIgnored('@alice:example.org'), isTrue);
  });
}
