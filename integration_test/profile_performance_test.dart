import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/profile/user_profile_screen.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkProfileGateway implements UserProfileGateway {
  MatrixUserProfile own = const MatrixUserProfile(
    userId: '@benchmark:example.org',
    displayName: 'Benchmark User',
  );
  MatrixUserProfile other = const MatrixUserProfile(
    userId: '@alice:example.org',
    displayName: 'Alice',
  );
  final ignored = <String>{};
  final blocked = <String>{};

  @override
  Future<Set<String>> loadBlockedUserIds() async => <String>{...blocked};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<MatrixUserProfile> loadOwnProfile() async => own;

  @override
  Future<MatrixUserProfile> loadProfile(String userId) async => other;

  @override
  Future<String> openDirectMessage(String userId) async =>
      '!benchmark:example.org';

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
    own = own.copyWith(avatarUri: avatarUri, clearAvatar: avatarUri == null);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    own = own.copyWith(displayName: displayName);
  }
}

Map<String, dynamic> _record(String journey, Map<String, dynamic> result) =>
    <String, dynamic>{
      'journey': journey,
      'fixture': 'deterministic_profile_v1',
      ...result,
      'result': 'PASS',
    };

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('own profile mutations have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadOwnProfile();
    final avatar = Uri.parse('mxc://example.org/benchmark-avatar');

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.own(
          controller: controller,
          loadOnInit: false,
          pickAvatar: () async => avatar,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final displayNameResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('edit-display-name')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('profile-display-name-field')),
          'Benchmark Updated',
        );
        await tester.tap(find.byKey(const Key('profile-save-display-name')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.ownProfile.value?.displayName, 'Benchmark Updated');

    final avatarResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('change-profile-avatar')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.ownProfile.value?.avatarUri, avatar);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['profile_display_name_edit'] = _record(
      'profile_display_name_edit',
      displayNameResult,
    );
    binding.reportData!['profile_avatar_change'] = _record(
      'profile_avatar_change',
      avatarResult,
    );
  });

  testWidgets('other-user profile actions have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkProfileGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.loadUserProfile('@alice:example.org');
    String? openedRoom;

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen.user(
          controller: controller,
          userId: '@alice:example.org',
          loadOnInit: false,
          onOpenRoom: (roomId) => openedRoom = roomId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dmResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('profile-message')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(openedRoom, '!benchmark:example.org');

    final ignoreResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('profile-ignore')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.isIgnored('@alice:example.org'), isTrue);

    final blockResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('profile-block')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.isBlocked('@alice:example.org'), isTrue);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['profile_open_dm'] = _record(
      'profile_open_dm',
      dmResult,
    );
    binding.reportData!['profile_ignore'] = _record(
      'profile_ignore',
      ignoreResult,
    );
    binding.reportData!['profile_block'] = _record(
      'profile_block',
      blockResult,
    );
  });
}
