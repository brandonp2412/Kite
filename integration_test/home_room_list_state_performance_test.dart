import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/threads/thread_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('room filter change has zero late Flutter frames', (
    tester,
  ) async {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: HomeScreen(roomListStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-filter-people')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_filter_change'] = <String, dynamic>{
      'journey': 'room_list_filter_change',
      'fixture': 'deterministic_200_rooms_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('space change has zero late Flutter frames', (tester) async {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: HomeScreen(roomListStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('space-filter-kite-space')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(store.selectedSpaceId.value, 'kite-space');
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['space_filter_change'] = <String, dynamic>{
      'journey': 'space_filter_change',
      'fixture': 'deterministic_200_rooms_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('invite accept mutation has zero late Flutter frames', (
    tester,
  ) async {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    final inviteStore = RoomInviteStore(deterministicRoomInvites);
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: HomeScreen(roomListStore: store, inviteStore: inviteStore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('invite-accept-design-lab-invite')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(inviteStore.visibleInviteIds.value, isEmpty);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['invite_accept'] = <String, dynamic>{
      'journey': 'invite_accept',
      'fixture': 'deterministic_room_invite_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('read-all mutation has zero late Flutter frames', (tester) async {
    threadController.reset();
    addTearDown(threadController.reset);
    threadController.updateRoomUnreadThreadCount(
      roomId: 'bob',
      unreadThreadCount: 2,
    );
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: HomeScreen(roomListStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.roomSignal('bob').value.unreadThreadCount, 2);
    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('home-read-all')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(threadController.unreadThreadCountForRoom('bob').value, 0);
    expect(store.roomSignal('bob').value.unreadThreadCount, 0);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_read_all'] = <String, dynamic>{
      'journey': 'room_list_read_all',
      'fixture': 'deterministic_200_rooms_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'section, favourite and room move have zero late Flutter frames',
    (tester) async {
      final store = RoomListStateStore(
        deterministicRoomListEntries(BenchmarkFixture.rooms),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: HomeScreen(roomListStore: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(
            find.byKey(const Key('room-section-toggle-favourites')),
          );
          await tester.pumpAndSettle();
          await tester.longPress(find.byKey(const Key('room-alice')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('room-favourite-toggle-alice')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('room-section-move-alice-rooms')),
          );
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(store.roomSignal('alice').value.isFavourite, isTrue);
      expect(store.sectionIdFor('alice'), 'rooms');
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['room_list_sections'] = <String, dynamic>{
        'journey': 'room_list_section_favourite_move',
        'fixture': 'deterministic_sections_v1',
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets('visible room state mutation has zero late Flutter frames', (
    tester,
  ) async {
    final store = RoomListStateStore(
      deterministicRoomListEntries(BenchmarkFixture.rooms),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: HomeScreen(roomListStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final room = store.roomSignal('alice').value;
        store.update(
          room.copyWith(
            latestSender: 'Alice',
            latestEventBody: 'Leaf signal frame benchmark',
            unreadCount: 3,
            hasMention: true,
            isMuted: true,
            isFavourite: true,
          ),
        );
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_leaf_state_update'] = <String, dynamic>{
      'journey': 'room_list_leaf_state_update',
      'fixture': 'deterministic_200_rooms_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
