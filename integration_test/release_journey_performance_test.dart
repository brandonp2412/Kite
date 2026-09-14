import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/settings/notification_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkSettingsGateway implements SettingsGateway {
  @override
  Future<KiteSettings> load() async => const KiteSettings.defaults();

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {}

  @override
  Future<void> saveLanguage(String? languageTag) async {}

  @override
  Future<void> saveNotificationMaster(bool enabled) async {}

  @override
  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  }) async {}

  @override
  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  }) async {}

  @override
  Future<void> saveMessageNotificationSound(String? soundId) async {}

  @override
  Future<void> saveCallRingtone(String? soundId) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('3,000-room list scroll has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(benchmarkRooms: BenchmarkFixture.largeRoomListRooms),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      BenchmarkFixture.largeRoomListRooms,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final list = find.byKey(const Key('room-list'));
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1200), 5000);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_scroll_3000'] = <String, dynamic>{
      'journey': 'room_list_scroll',
      'fixture': 'deterministic_3000_rooms_v1',
      'roomCount': BenchmarkFixture.largeRoomListRooms.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('notification settings mutations have zero late Flutter frames', (
    tester,
  ) async {
    final controller = SettingsController(_BenchmarkSettingsGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          controller: controller,
          roomId: '!kite:example.org',
          roomName: 'Kite room',
          messageSounds: const <NotificationSoundOption>[
            NotificationSoundOption(id: 'soft', label: 'Soft'),
          ],
          callRingtones: const <NotificationSoundOption>[
            NotificationSoundOption(id: 'bright', label: 'Bright'),
          ],
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final master = find.byKey(const Key('notification-master'));
        await tester.tap(master);
        await tester.pump();
        await tester.tap(master);
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('notification-category-mentions')),
        );
        await tester.pump();

        final roomMode = find.byKey(const Key('room-notification-mode'));
        await tester.ensureVisible(roomMode);
        await tester.tap(roomMode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mentions only').last);
        await tester.pumpAndSettle();

        final messageSound = find.byKey(
          const Key('message-notification-sound'),
        );
        await tester.ensureVisible(messageSound);
        await tester.tap(messageSound);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Soft').last);
        await tester.pumpAndSettle();

        final callRingtone = find.byKey(
          const Key('call-notification-ringtone'),
        );
        await tester.ensureVisible(callRingtone);
        await tester.tap(callRingtone);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bright').last);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.settings.value.notifications.masterEnabled, isTrue);
    expect(
      controller.settings.value.notifications.enabledCategories,
      isNot(contains(NotificationCategory.mentions)),
    );
    expect(
      controller.settings.value.notifications.roomMode('!kite:example.org'),
      RoomNotificationMode.mentionsOnly,
    );
    expect(controller.settings.value.notifications.messageSoundId, 'soft');
    expect(controller.settings.value.notifications.callRingtoneId, 'bright');

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['notification_settings_mutations'] = <String, dynamic>{
      'journey': 'notification_settings_mutations',
      'fixture': 'deterministic_notification_settings_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('composer keyboard appearance has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final composer = find.descendant(
      of: find.byKey(const Key('composer')),
      matching: find.byType(TextField),
    );
    expect(composer, findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(composer);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_keyboard'] = <String, dynamic>{
      'journey': 'composer_keyboard',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
