import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/settings/privacy_user_controls_screen.dart';

final class _DeferredPrivacyGateway implements UserProfileGateway {
  final ignored = Completer<Set<String>>();
  final blocked = Completer<Set<String>>();

  @override
  Future<Set<String>> loadIgnoredUserIds() => ignored.future;

  @override
  Future<Set<String>> loadBlockedUserIds() => blocked.future;

  @override
  Future<void> setUserIgnored({
    required String userId,
    required bool ignored,
  }) async {}

  @override
  Future<void> setUserBlocked({
    required String userId,
    required bool blocked,
  }) async {}

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

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('privacy loading preserves primary geometry at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final gateway = _DeferredPrivacyGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PrivacyUserControlsScreen(controller: controller)),
    );
    await tester.pump();

    final list = find.byKey(const Key('privacy-user-controls-list'));
    final loading = find.byKey(const Key('privacy-user-controls-loading-slot'));
    final status = find.byKey(const Key('privacy-user-controls-status-slot'));
    final listRect = _rectOf(tester, list);
    final loadingRect = _rectOf(tester, loading);
    final statusRect = _rectOf(tester, status);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), listRect);
      expect(_rectOf(tester, loading), loadingRect);
      expect(_rectOf(tester, status), statusRect);
      expect(tester.takeException(), isNull);
    }

    gateway.ignored.complete(const <String>{});
    gateway.blocked.complete(const <String>{});
    await tester.pump();
    expect(_rectOf(tester, loading), loadingRect);
    expect(_rectOf(tester, status), statusRect);
  });
}
