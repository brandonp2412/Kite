import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('app root startup composition has zero late Flutter frames', (
    tester,
  ) async {
    selectedRoomId.value = 'kite';
    KiteTheme.warmUp();
    final roomListStore = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final inviteStore = RoomInviteStore(deterministicRoomInvites);
    timelineController.messagesFor('kite');

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.pumpWidget(
          KiteApp(
            themeMode: ThemeMode.light,
            home: HomeScreen(
              roomListStore: roomListStore,
              inviteStore: inviteStore,
            ),
          ),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('room-list')), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['app_root_startup'] = <String, dynamic>{
      'journey': 'app_root_startup',
      'fixture': 'preloaded_deterministic_kite_app_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
