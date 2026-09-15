import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/profile/user_profile_controller.dart';
import 'package:kite/features/settings/privacy_user_controls_screen.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkPrivacyGateway implements UserProfileGateway {
  final ignored = <String>{'@ignored:example.org'};
  final blocked = <String>{'@blocked:example.org'};

  @override
  Future<Set<String>> loadIgnoredUserIds() async => <String>{...ignored};

  @override
  Future<Set<String>> loadBlockedUserIds() async => <String>{...blocked};

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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('privacy user controls have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkPrivacyGateway();
    final controller = UserProfileController(gateway);
    addTearDown(controller.dispose);
    await controller.refreshPrivacyControls();

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyUserControlsScreen(
          controller: controller,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unignoreResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('unignore-user-@ignored:example.org')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.isIgnored('@ignored:example.org'), isFalse);

    final unblockResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('unblock-user-@blocked:example.org')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.isBlocked('@blocked:example.org'), isFalse);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['privacy_user_unignore'] = <String, dynamic>{
      'journey': 'privacy_user_unignore',
      'fixture': 'deterministic_privacy_controls_v1',
      ...unignoreResult,
      'result': 'PASS',
    };
    binding.reportData!['privacy_user_unblock'] = <String, dynamic>{
      'journey': 'privacy_user_unblock',
      'fixture': 'deterministic_privacy_controls_v1',
      ...unblockResult,
      'result': 'PASS',
    };
  });
}
