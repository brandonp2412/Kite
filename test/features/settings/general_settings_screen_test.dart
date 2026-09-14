import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/general_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class _FakeSettingsGateway implements SettingsGateway {
  KiteSettings loaded = const KiteSettings.defaults();
  KiteAppearanceMode? savedAppearance;
  String? savedLanguage;

  @override
  Future<KiteSettings> load() async => loaded;

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {
    savedAppearance = appearanceMode;
  }

  @override
  Future<void> saveLanguage(String? languageTag) async {
    savedLanguage = languageTag;
  }

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

Widget _app(SettingsController controller) {
  return MaterialApp(
    home: GeneralSettingsScreen(
      controller: controller,
      loadOnInit: false,
      languages: const <KiteLanguageOption>[
        KiteLanguageOption(tag: 'en', label: 'English'),
        KiteLanguageOption(tag: 'en-NZ', label: 'English (New Zealand)'),
        KiteLanguageOption(tag: 'de', label: 'Deutsch'),
      ],
    ),
  );
}

void main() {
  testWidgets('shows system, light, dark and black appearance modes', (
    tester,
  ) async {
    final controller = SettingsController(_FakeSettingsGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    for (final mode in KiteAppearanceMode.values) {
      expect(find.byKey(Key('appearance-${mode.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('language-picker')), findsOneWidget);
    expect(find.text('Use system language'), findsOneWidget);
  });

  testWidgets('persists appearance and language selections', (tester) async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const Key('appearance-dark')));
    await tester.pumpAndSettle();
    expect(gateway.savedAppearance, KiteAppearanceMode.dark);
    expect(controller.settings.value.appearanceMode, KiteAppearanceMode.dark);

    await tester.tap(find.byKey(const Key('language-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English (New Zealand)').last);
    await tester.pumpAndSettle();
    expect(gateway.savedLanguage, 'en-NZ');
    expect(controller.settings.value.languageTag, 'en-NZ');

    await tester.tap(find.byKey(const Key('language-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use system language').last);
    await tester.pumpAndSettle();
    expect(gateway.savedLanguage, isNull);
    expect(controller.settings.value.languageTag, isNull);
  });

  testWidgets('loads persisted selections without exposing unsupported tags', (
    tester,
  ) async {
    final gateway = _FakeSettingsGateway()
      ..loaded = const KiteSettings(
        appearanceMode: KiteAppearanceMode.black,
        languageTag: 'fr',
        notifications: NotificationPreferences.defaults(),
      );
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));

    final appearanceGroup = tester.widget<RadioGroup<KiteAppearanceMode>>(
      find.byType(RadioGroup<KiteAppearanceMode>),
    );
    expect(appearanceGroup.groupValue, KiteAppearanceMode.black);

    final languagePicker = tester.widget<DropdownButton<String>>(
      find.byKey(const Key('language-picker')),
    );
    expect(languagePicker.value, '__kite_system_language__');
    expect(find.text('fr'), findsNothing);
  });
}
