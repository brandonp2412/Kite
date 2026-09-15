import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/settings_controller.dart';

final class _FakeSettingsGateway implements SettingsGateway {
  KiteSettings loaded = const KiteSettings.defaults();
  Object? loadError;
  Object? saveError;
  Completer<KiteSettings>? deferredLoad;
  Completer<void>? deferredAppearanceSave;
  int loadCalls = 0;
  KiteAppearanceMode? savedAppearance;
  String? savedLanguage;
  bool savedSystemLanguage = false;
  bool? savedMaster;
  final categoryUpdates = <(NotificationCategory, bool)>[];
  final roomModeUpdates = <(String, RoomNotificationMode)>[];
  final messageSoundUpdates = <String?>[];
  final callRingtoneUpdates = <String?>[];

  @override
  Future<KiteSettings> load() async {
    loadCalls += 1;
    if (loadError case final error?) throw error;
    final deferred = deferredLoad;
    if (deferred != null) return deferred.future;
    return loaded;
  }

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {
    if (saveError case final error?) throw error;
    final deferred = deferredAppearanceSave;
    if (deferred != null) await deferred.future;
    savedAppearance = appearanceMode;
  }

  @override
  Future<void> saveLanguage(String? languageTag) async {
    if (saveError case final error?) throw error;
    savedLanguage = languageTag;
    savedSystemLanguage = languageTag == null;
  }

  @override
  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  }) async {
    if (saveError case final error?) throw error;
    categoryUpdates.add((category, enabled));
  }

  @override
  Future<void> saveNotificationMaster(bool enabled) async {
    if (saveError case final error?) throw error;
    savedMaster = enabled;
  }

  @override
  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  }) async {
    if (saveError case final error?) throw error;
    roomModeUpdates.add((roomId, mode));
  }

  @override
  Future<void> saveMessageNotificationSound(String? soundId) async {
    if (saveError case final error?) throw error;
    messageSoundUpdates.add(soundId);
  }

  @override
  Future<void> saveCallRingtone(String? soundId) async {
    if (saveError case final error?) throw error;
    callRingtoneUpdates.add(soundId);
  }
}

void main() {
  test('save is rejected while a settings load is in flight', () async {
    final deferred = Completer<KiteSettings>();
    final gateway = _FakeSettingsGateway()..deferredLoad = deferred;
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isLoading.value, isTrue);

    expect(await controller.setAppearance(KiteAppearanceMode.dark), isFalse);
    expect(gateway.savedAppearance, isNull);

    deferred.complete(const KiteSettings.defaults());
    await loading;
    expect(controller.settings.value.appearanceMode, KiteAppearanceMode.system);
  });

  test('load is rejected while a settings save is in flight', () async {
    final deferred = Completer<void>();
    final gateway = _FakeSettingsGateway()..deferredAppearanceSave = deferred;
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    final saving = controller.setAppearance(KiteAppearanceMode.dark);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isSaving.value, isTrue);

    await controller.load();
    expect(gateway.loadCalls, 0);

    deferred.complete();
    expect(await saving, isTrue);
    expect(controller.settings.value.appearanceMode, KiteAppearanceMode.dark);
  });

  test(
    'loads general settings while preserving known state on failure',
    () async {
      final gateway = _FakeSettingsGateway()
        ..loaded = const KiteSettings(
          appearanceMode: KiteAppearanceMode.black,
          languageTag: 'en-NZ',
          notifications: NotificationPreferences.defaults(),
        );
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.hasLoaded.value, isTrue);
      expect(
        controller.settings.value.appearanceMode,
        KiteAppearanceMode.black,
      );
      expect(controller.settings.value.languageTag, 'en-NZ');

      gateway.loadError = StateError('access_token=secret');
      await controller.load();

      expect(
        controller.settings.value.appearanceMode,
        KiteAppearanceMode.black,
      );
      expect(
        controller.errorMessage.value,
        'Kite could not load your settings.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );

  test(
    'rejects malformed persisted settings without replacing known state',
    () async {
      final gateway = _FakeSettingsGateway()
        ..loaded = const KiteSettings(
          appearanceMode: KiteAppearanceMode.dark,
          languageTag: 'en-NZ',
          notifications: NotificationPreferences.defaults(),
        );
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      gateway.loaded = const KiteSettings(
        appearanceMode: KiteAppearanceMode.black,
        languageTag: ' en-NZ ',
        notifications: NotificationPreferences(
          masterEnabled: true,
          enabledCategories: <NotificationCategory>{
            NotificationCategory.messages,
          },
          roomModes: <String, RoomNotificationMode>{
            '!room:example.org': RoomNotificationMode.mentionsOnly,
          },
        ),
      );
      await controller.load();

      expect(controller.settings.value.appearanceMode, KiteAppearanceMode.dark);
      expect(controller.settings.value.languageTag, 'en-NZ');
      expect(
        controller.errorMessage.value,
        'Kite received invalid settings data.',
      );
    },
  );

  test('loaded notification collections are immutable snapshots', () async {
    final categories = <NotificationCategory>{NotificationCategory.messages};
    final roomModes = <String, RoomNotificationMode>{
      '!room:example.org': RoomNotificationMode.mentionsOnly,
    };
    final gateway = _FakeSettingsGateway()
      ..loaded = KiteSettings(
        appearanceMode: KiteAppearanceMode.system,
        languageTag: null,
        notifications: NotificationPreferences(
          masterEnabled: true,
          enabledCategories: categories,
          roomModes: roomModes,
        ),
      );
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    await controller.load();
    categories.add(NotificationCategory.calls);
    roomModes.clear();

    expect(
      controller.settings.value.notifications.enabledCategories,
      <NotificationCategory>{NotificationCategory.messages},
    );
    expect(
      controller.settings.value.notifications.roomModes,
      <String, RoomNotificationMode>{
        '!room:example.org': RoomNotificationMode.mentionsOnly,
      },
    );
  });

  test('persists system, light, dark, and black appearance modes', () async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    for (final mode in KiteAppearanceMode.values) {
      expect(await controller.setAppearance(mode), isTrue);
      expect(gateway.savedAppearance, mode);
      expect(controller.settings.value.appearanceMode, mode);
    }
  });

  test('normalizes language tags and supports system language', () async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.setLanguage(' pt_BR '), isTrue);
    expect(gateway.savedLanguage, 'pt-BR');
    expect(controller.settings.value.languageTag, 'pt-BR');

    expect(await controller.setLanguage(null), isTrue);
    expect(gateway.savedSystemLanguage, isTrue);
    expect(controller.settings.value.languageTag, isNull);

    expect(await controller.setLanguage('not a locale'), isFalse);
    expect(controller.errorMessage.value, 'Choose a valid language.');
  });

  test('master notification setting gates category effective state', () async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    expect(
      controller.settings.value.notifications.isEnabled(
        NotificationCategory.messages,
      ),
      isTrue,
    );

    expect(await controller.setNotificationMaster(false), isTrue);
    expect(gateway.savedMaster, isFalse);
    expect(
      controller.settings.value.notifications.isEnabled(
        NotificationCategory.messages,
      ),
      isFalse,
    );
  });

  test('persists message, mention, and call notification categories', () async {
    final gateway = _FakeSettingsGateway();
    final controller = SettingsController(gateway);
    addTearDown(controller.dispose);

    for (final category in NotificationCategory.values) {
      expect(await controller.setNotificationCategory(category, false), isTrue);
      expect(
        controller.settings.value.notifications.enabledCategories,
        isNot(contains(category)),
      );
    }

    expect(gateway.categoryUpdates, <(NotificationCategory, bool)>[
      (NotificationCategory.messages, false),
      (NotificationCategory.mentions, false),
      (NotificationCategory.calls, false),
    ]);
  });

  test(
    'persists per-room notification overrides and removes inherited state',
    () async {
      final gateway = _FakeSettingsGateway();
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.setRoomNotificationMode(
          ' !room:example.org ',
          RoomNotificationMode.mentionsOnly,
        ),
        isTrue,
      );
      expect(
        controller.settings.value.notifications.roomMode('!room:example.org'),
        RoomNotificationMode.mentionsOnly,
      );

      expect(
        await controller.setRoomNotificationMode(
          '!room:example.org',
          RoomNotificationMode.inherit,
        ),
        isTrue,
      );
      expect(
        controller.settings.value.notifications.roomMode('!room:example.org'),
        RoomNotificationMode.inherit,
      );
      expect(controller.settings.value.notifications.roomModes, isEmpty);
      expect(gateway.roomModeUpdates, <(String, RoomNotificationMode)>[
        ('!room:example.org', RoomNotificationMode.mentionsOnly),
        ('!room:example.org', RoomNotificationMode.inherit),
      ]);
    },
  );

  test(
    'rejects malformed room IDs before touching the settings gateway',
    () async {
      final gateway = _FakeSettingsGateway();
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.setRoomNotificationMode(
          'room-without-sigil',
          RoomNotificationMode.mute,
        ),
        isFalse,
      );
      expect(gateway.roomModeUpdates, isEmpty);
      expect(controller.errorMessage.value, 'Choose a valid Matrix room.');
    },
  );

  test(
    'persists custom message sound and call ringtone with default reset',
    () async {
      final gateway = _FakeSettingsGateway();
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      expect(
        await controller.setMessageNotificationSound(' message-soft '),
        isTrue,
      );
      expect(
        controller.settings.value.notifications.messageSoundId,
        'message-soft',
      );
      expect(gateway.messageSoundUpdates, <String?>['message-soft']);

      expect(await controller.setCallRingtone(' call-loud '), isTrue);
      expect(
        controller.settings.value.notifications.callRingtoneId,
        'call-loud',
      );
      expect(gateway.callRingtoneUpdates, <String?>['call-loud']);

      expect(await controller.setMessageNotificationSound('  '), isTrue);
      expect(controller.settings.value.notifications.messageSoundId, isNull);
      expect(gateway.messageSoundUpdates, <String?>['message-soft', null]);

      expect(await controller.setCallRingtone(null), isTrue);
      expect(controller.settings.value.notifications.callRingtoneId, isNull);
      expect(gateway.callRingtoneUpdates, <String?>['call-loud', null]);
    },
  );

  test(
    'failed saves leave the previous in-memory settings untouched',
    () async {
      final gateway = _FakeSettingsGateway()
        ..saveError = StateError('recovery_key=secret');
      final controller = SettingsController(gateway);
      addTearDown(controller.dispose);

      expect(await controller.setAppearance(KiteAppearanceMode.dark), isFalse);
      expect(
        controller.settings.value.appearanceMode,
        KiteAppearanceMode.system,
      );
      expect(
        controller.errorMessage.value,
        'Kite could not save your appearance setting.',
      );
      expect(controller.errorMessage.value, isNot(contains('secret')));

      expect(
        await controller.setRoomNotificationMode(
          '!room:example.org',
          RoomNotificationMode.mute,
        ),
        isFalse,
      );
      expect(controller.settings.value.notifications.roomModes, isEmpty);
      expect(controller.errorMessage.value, isNot(contains('secret')));

      expect(
        await controller.setMessageNotificationSound('secret-tone'),
        isFalse,
      );
      expect(controller.settings.value.notifications.messageSoundId, isNull);
      expect(controller.errorMessage.value, isNot(contains('secret')));
    },
  );
}
