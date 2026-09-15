import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/settings/general_settings_screen.dart';
import 'package:kite/features/settings/notification_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';
import 'package:kite/features/settings/support_settings_controller.dart';
import 'package:kite/features/settings/support_settings_screen.dart';

final class _GoldenSettingsGateway implements SettingsGateway {
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

final class _GoldenSupportGateway implements SupportSettingsGateway {
  @override
  Future<StorageUsageSnapshot> loadStorageUsage() async {
    return const StorageUsageSnapshot(
      mediaCacheBytes: 24 * 1024 * 1024,
      presentationCacheBytes: 3 * 1024 * 1024,
      diagnosticLogBytes: 640 * 1024,
    );
  }

  @override
  Future<void> clearMediaCache() async {}

  @override
  Future<void> clearPresentationCache() async {}

  @override
  Future<AppAboutInfo> loadAboutInfo() async {
    return const AppAboutInfo(
      version: '1.2.3',
      buildNumber: '45',
      licenseCount: 37,
    );
  }

  @override
  Future<SanitizedDiagnosticBundle> prepareSanitizedDiagnostics() async {
    return SanitizedDiagnosticBundle(
      generatedAt: DateTime.utc(2026, 9, 15, 2),
      structuredEventCount: 12,
      crashReportCount: 1,
    );
  }

  @override
  Future<void> submitProblemReport(ProblemReportRequest report) async {}
}

Future<void> _configureViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _materialApp({required ThemeMode themeMode, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: KiteTheme.light,
    darkTheme: KiteTheme.dark,
    themeMode: themeMode,
    home: home,
  );
}

void main() {
  for (final variant in <(String, ThemeMode)>[
    ('light', ThemeMode.light),
    ('dark', ThemeMode.dark),
  ]) {
    testWidgets('approved general settings baseline - ${variant.$1}', (
      tester,
    ) async {
      await _configureViewport(tester);
      final controller = SettingsController(_GoldenSettingsGateway());
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        _materialApp(
          themeMode: variant.$2,
          home: GeneralSettingsScreen(
            controller: controller,
            loadOnInit: false,
            languages: const <KiteLanguageOption>[
              KiteLanguageOption(tag: 'en', label: 'English'),
              KiteLanguageOption(tag: 'en-NZ', label: 'English (New Zealand)'),
              KiteLanguageOption(tag: 'de', label: 'Deutsch'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(GeneralSettingsScreen),
        matchesGoldenFile('goldens/settings_general_${variant.$1}.png'),
      );
    });

    testWidgets('approved notification settings baseline - ${variant.$1}', (
      tester,
    ) async {
      await _configureViewport(tester);
      final controller = SettingsController(_GoldenSettingsGateway());
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        _materialApp(
          themeMode: variant.$2,
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

      await expectLater(
        find.byType(NotificationSettingsScreen),
        matchesGoldenFile('goldens/settings_notifications_${variant.$1}.png'),
      );
    });

    testWidgets('approved support settings baseline - ${variant.$1}', (
      tester,
    ) async {
      await _configureViewport(tester);
      final controller = SupportSettingsController(_GoldenSupportGateway());
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        _materialApp(
          themeMode: variant.$2,
          home: SupportSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SupportSettingsScreen),
        matchesGoldenFile('goldens/settings_support_${variant.$1}.png'),
      );
    });
  }
}
