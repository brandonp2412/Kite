import 'package:signals/signals.dart';

enum KiteAppearanceMode { system, light, dark, black }

enum NotificationCategory { messages, mentions, calls }

final class NotificationPreferences {
  const NotificationPreferences({
    required this.masterEnabled,
    required this.enabledCategories,
  });

  const NotificationPreferences.defaults()
    : masterEnabled = true,
      enabledCategories = const <NotificationCategory>{
        NotificationCategory.messages,
        NotificationCategory.mentions,
        NotificationCategory.calls,
      };

  final bool masterEnabled;
  final Set<NotificationCategory> enabledCategories;

  bool isEnabled(NotificationCategory category) =>
      masterEnabled && enabledCategories.contains(category);

  NotificationPreferences copyWith({
    bool? masterEnabled,
    Set<NotificationCategory>? enabledCategories,
  }) {
    return NotificationPreferences(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      enabledCategories: Set<NotificationCategory>.unmodifiable(
        enabledCategories ?? this.enabledCategories,
      ),
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
    if (isLoading.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    try {
      settings.value = await _gateway.load();
      hasLoaded.value = true;
    } catch (_) {
      errorMessage.value = 'Kite could not load your settings.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> setAppearance(KiteAppearanceMode appearanceMode) async {
    if (isSaving.value) return false;
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
    if (isSaving.value) return false;
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
    if (isSaving.value) return false;
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
    if (isSaving.value) return false;
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
