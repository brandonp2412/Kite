import 'package:signals/signals.dart';

enum KiteAppearanceMode { system, light, dark, black }

enum NotificationCategory { messages, mentions, calls }

enum RoomNotificationMode { inherit, allMessages, mentionsOnly, mute }

final class NotificationPreferences {
  const NotificationPreferences({
    required this.masterEnabled,
    required this.enabledCategories,
    this.roomModes = const <String, RoomNotificationMode>{},
    this.messageSoundId,
    this.callRingtoneId,
  });

  const NotificationPreferences.defaults()
    : masterEnabled = true,
      enabledCategories = const <NotificationCategory>{
        NotificationCategory.messages,
        NotificationCategory.mentions,
        NotificationCategory.calls,
      },
      roomModes = const <String, RoomNotificationMode>{},
      messageSoundId = null,
      callRingtoneId = null;

  final bool masterEnabled;
  final Set<NotificationCategory> enabledCategories;
  final Map<String, RoomNotificationMode> roomModes;
  final String? messageSoundId;
  final String? callRingtoneId;

  bool isEnabled(NotificationCategory category) =>
      masterEnabled && enabledCategories.contains(category);

  RoomNotificationMode roomMode(String roomId) =>
      roomModes[roomId] ?? RoomNotificationMode.inherit;

  NotificationPreferences copyWith({
    bool? masterEnabled,
    Set<NotificationCategory>? enabledCategories,
    Map<String, RoomNotificationMode>? roomModes,
    String? messageSoundId,
    bool useDefaultMessageSound = false,
    String? callRingtoneId,
    bool useDefaultCallRingtone = false,
  }) {
    return NotificationPreferences(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      enabledCategories: Set<NotificationCategory>.unmodifiable(
        enabledCategories ?? this.enabledCategories,
      ),
      roomModes: Map<String, RoomNotificationMode>.unmodifiable(
        roomModes ?? this.roomModes,
      ),
      messageSoundId: useDefaultMessageSound
          ? null
          : messageSoundId ?? this.messageSoundId,
      callRingtoneId: useDefaultCallRingtone
          ? null
          : callRingtoneId ?? this.callRingtoneId,
    );
  }
}

final class KiteSettings {
  const KiteSettings({
    required this.appearanceMode,
    required this.languageTag,
    required this.notifications,
  });

  const KiteSettings.defaults()
    : appearanceMode = KiteAppearanceMode.system,
      languageTag = null,
      notifications = const NotificationPreferences.defaults();

  final KiteAppearanceMode appearanceMode;
  final String? languageTag;
  final NotificationPreferences notifications;

  KiteSettings copyWith({
    KiteAppearanceMode? appearanceMode,
    String? languageTag,
    bool useSystemLanguage = false,
    NotificationPreferences? notifications,
  }) {
    return KiteSettings(
      appearanceMode: appearanceMode ?? this.appearanceMode,
      languageTag: useSystemLanguage ? null : languageTag ?? this.languageTag,
      notifications: notifications ?? this.notifications,
    );
  }
}

abstract interface class SettingsGateway {
  Future<KiteSettings> load();

  Future<void> saveAppearance(KiteAppearanceMode appearanceMode);

  Future<void> saveLanguage(String? languageTag);

  Future<void> saveNotificationMaster(bool enabled);

  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  });

  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  });

  Future<void> saveMessageNotificationSound(String? soundId);

  Future<void> saveCallRingtone(String? soundId);
}

final class SettingsController {
  SettingsController(this._gateway);

  final SettingsGateway _gateway;

  final settings = signal(const KiteSettings.defaults());
  final hasLoaded = signal(false);
  final isLoading = signal(false);
  final isSaving = signal(false);
  final errorMessage = signal<String?>(null);

  Future<void> load() async {
    if (isLoading.value || isSaving.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    try {
      final loaded = await _gateway.load();
      final snapshot = _validatedSnapshot(loaded);
      if (snapshot == null) {
        errorMessage.value = 'Kite received invalid settings data.';
        return;
      }
      settings.value = snapshot;
      hasLoaded.value = true;
    } catch (_) {
      errorMessage.value = 'Kite could not load your settings.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> setAppearance(KiteAppearanceMode appearanceMode) async {
    if (isLoading.value || isSaving.value) return false;
    final previous = settings.value;

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.saveAppearance(appearanceMode);
      settings.value = previous.copyWith(appearanceMode: appearanceMode);
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not save your appearance setting.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setLanguage(String? languageTag) async {
    if (isLoading.value || isSaving.value) return false;
    final normalized = _normalizeLanguageTag(languageTag);
    if (languageTag != null && normalized == null) {
      errorMessage.value = 'Choose a valid language.';
      return false;
    }
    final previous = settings.value;

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.saveLanguage(normalized);
      settings.value = previous.copyWith(
        languageTag: normalized,
        useSystemLanguage: normalized == null,
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not save your language setting.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setNotificationMaster(bool enabled) async {
    if (isLoading.value || isSaving.value) return false;
    final previous = settings.value;

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.saveNotificationMaster(enabled);
      settings.value = previous.copyWith(
        notifications: previous.notifications.copyWith(masterEnabled: enabled),
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not save notification settings.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setNotificationCategory(
    NotificationCategory category,
    bool enabled,
  ) async {
    if (isLoading.value || isSaving.value) return false;
    final previous = settings.value;
    final categories = <NotificationCategory>{
      ...previous.notifications.enabledCategories,
    };
    if (enabled) {
      categories.add(category);
    } else {
      categories.remove(category);
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.saveNotificationCategory(
        category: category,
        enabled: enabled,
      );
      settings.value = previous.copyWith(
        notifications: previous.notifications.copyWith(
          enabledCategories: categories,
        ),
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not save notification settings.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setRoomNotificationMode(
    String roomId,
    RoomNotificationMode mode,
  ) async {
    if (isLoading.value || isSaving.value) return false;
    final normalizedRoomId = roomId.trim();
    if (!_isValidRoomId(normalizedRoomId)) {
      errorMessage.value = 'Choose a valid Matrix room.';
      return false;
    }
    final previous = settings.value;
    final roomModes = <String, RoomNotificationMode>{
      ...previous.notifications.roomModes,
    };
    if (mode == RoomNotificationMode.inherit) {
      roomModes.remove(normalizedRoomId);
    } else {
      roomModes[normalizedRoomId] = mode;
    }

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await _gateway.saveRoomNotificationMode(
        roomId: normalizedRoomId,
        mode: mode,
      );
      settings.value = previous.copyWith(
        notifications: previous.notifications.copyWith(roomModes: roomModes),
      );
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not save room notification settings.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> setMessageNotificationSound(String? soundId) async {
    return _setNotificationSound(
      soundId: soundId,
      save: _gateway.saveMessageNotificationSound,
      success: (previous, normalizedSoundId) => previous.copyWith(
        notifications: previous.notifications.copyWith(
          messageSoundId: normalizedSoundId,
          useDefaultMessageSound: normalizedSoundId == null,
        ),
      ),
      failureMessage: 'Kite could not save the message notification sound.',
    );
  }

  Future<bool> setCallRingtone(String? soundId) async {
    return _setNotificationSound(
      soundId: soundId,
      save: _gateway.saveCallRingtone,
      success: (previous, normalizedSoundId) => previous.copyWith(
        notifications: previous.notifications.copyWith(
          callRingtoneId: normalizedSoundId,
          useDefaultCallRingtone: normalizedSoundId == null,
        ),
      ),
      failureMessage: 'Kite could not save the call ringtone.',
    );
  }

  Future<bool> _setNotificationSound({
    required String? soundId,
    required Future<void> Function(String? soundId) save,
    required KiteSettings Function(KiteSettings previous, String? soundId)
    success,
    required String failureMessage,
  }) async {
    if (isLoading.value || isSaving.value) return false;
    final normalizedSoundId = _normalizeSoundId(soundId);
    final previous = settings.value;

    isSaving.value = true;
    errorMessage.value = null;
    try {
      await save(normalizedSoundId);
      settings.value = success(previous, normalizedSoundId);
      return true;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  KiteSettings? _validatedSnapshot(KiteSettings loaded) {
    final languageTag = loaded.languageTag;
    if (languageTag != null &&
        _normalizeLanguageTag(languageTag) != languageTag) {
      return null;
    }
    final notifications = loaded.notifications;
    for (final entry in notifications.roomModes.entries) {
      if (!_isValidRoomId(entry.key) ||
          entry.value == RoomNotificationMode.inherit) {
        return null;
      }
    }
    if (!_isNormalizedSoundId(notifications.messageSoundId) ||
        !_isNormalizedSoundId(notifications.callRingtoneId)) {
      return null;
    }
    return KiteSettings(
      appearanceMode: loaded.appearanceMode,
      languageTag: languageTag,
      notifications: NotificationPreferences(
        masterEnabled: notifications.masterEnabled,
        enabledCategories: Set<NotificationCategory>.unmodifiable(
          notifications.enabledCategories,
        ),
        roomModes: Map<String, RoomNotificationMode>.unmodifiable(
          notifications.roomModes,
        ),
        messageSoundId: notifications.messageSoundId,
        callRingtoneId: notifications.callRingtoneId,
      ),
    );
  }

  bool _isValidRoomId(String roomId) {
    final separator = roomId.indexOf(':');
    return roomId == roomId.trim() &&
        roomId.startsWith('!') &&
        separator > 1 &&
        separator < roomId.length - 1 &&
        !roomId.contains(RegExp(r'\s'));
  }

  bool _isNormalizedSoundId(String? soundId) =>
      soundId == null || _normalizeSoundId(soundId) == soundId;

  String? _normalizeSoundId(String? soundId) {
    final trimmed = soundId?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeLanguageTag(String? languageTag) {
    if (languageTag == null) return null;
    final trimmed = languageTag.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$').hasMatch(trimmed)) {
      return null;
    }
    return trimmed.replaceAll('_', '-');
  }

  void dispose() {
    settings.dispose();
    hasLoaded.dispose();
    isLoading.dispose();
    isSaving.dispose();
    errorMessage.dispose();
  }
}
