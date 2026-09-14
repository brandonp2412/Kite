import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/notification_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class _FakeSettingsGateway implements SettingsGateway {
  KiteSettings loaded = const KiteSettings.defaults();
  bool? savedMaster;
  final categoryUpdates = <(NotificationCategory, bool)>[];
  final roomUpdates = <(String, RoomNotificationMode)>[];
  final messageSounds = <String?>[];
  final callRingtones = <String?>[];

  @override
  Future<KiteSettings> load() async => loaded;

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {}

  @override
  Future<void> saveLanguage(String? languageTag) async {}

  @override
  Future<void> saveNotificationMaster(bool enabled) async {
    savedMaster = enabled;
  }

  @override
  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  }) async {
    categoryUpdates.add((category, enabled));
  }

  @override
  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  }) async {
    roomUpdates.add((roomId, mode));
  }

  @override
  Future<void> saveMessageNotificationSound(String? soundId) async {
    messageSounds.add(soundId);
  }

  @override
  Future<void> saveCallRingtone(String? soundId) async {
    callRingtones.add(soundId);
  }
}

Widget _app(SettingsController controller) {
  return MaterialApp(
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
  );
}

void main() {
  testWidgets('wires master, categories and per-room notification controls', (
    tester,
  ) async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const Key('notification-master')));
    await tester.pump();
    expect(gateway.savedMaster, isFalse);
    expect(controller.settings.value.notifications.masterEnabled, isFalse);

    await tester.tap(find.byKey(const Key('notification-master')));
    await tester.pump();
    expect(gateway.savedMaster, isTrue);

    await tester.tap(find.byKey(const Key('notification-category-mentions')));
    await tester.pump();
    expect(gateway.categoryUpdates, <(NotificationCategory, bool)>[
      (NotificationCategory.mentions, false),
    ]);

    await tester.tap(find.byKey(const Key('room-notification-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentions only').last);
    await tester.pumpAndSettle();
    expect(gateway.roomUpdates, <(String, RoomNotificationMode)>[
      ('!kite:example.org', RoomNotificationMode.mentionsOnly),
    ]);
  });

  testWidgets('wires message and call sound selection with default reset', (
    tester,
  ) async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const Key('message-notification-sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soft').last);
    await tester.pumpAndSettle();
    expect(gateway.messageSounds, <String?>['soft']);

    final callRingtone = find.byKey(const Key('call-notification-ringtone'));
    await tester.ensureVisible(callRingtone);
    await tester.pumpAndSettle();
    await tester.tap(callRingtone);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bright').last);
    await tester.pumpAndSettle();
    expect(gateway.callRingtones, <String?>['bright']);

    final messageSound = find.byKey(const Key('message-notification-sound'));
    await tester.ensureVisible(messageSound);
    await tester.pumpAndSettle();
    await tester.tap(messageSound);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default').last);
    await tester.pumpAndSettle();
    expect(gateway.messageSounds, <String?>['soft', null]);
  });

  testWidgets('keeps controls visible while the notification master is off', (
    tester,
  ) async {
    final gateway = _FakeSettingsGateway()
      ..loaded = const KiteSettings(
        appearanceMode: KiteAppearanceMode.system,
        languageTag: null,
        notifications: NotificationPreferences(
          masterEnabled: false,
          enabledCategories: <NotificationCategory>{
            NotificationCategory.messages,
            NotificationCategory.mentions,
            NotificationCategory.calls,
          },
        ),
      );
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));

    expect(find.byKey(const Key('notification-category-messages')), findsOne);
    expect(find.byKey(const Key('notification-category-mentions')), findsOne);
    expect(find.byKey(const Key('notification-category-calls')), findsOne);
    expect(find.byKey(const Key('room-notification-mode')), findsOne);
    expect(find.byKey(const Key('message-notification-sound')), findsOne);
  });
}
