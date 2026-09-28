// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/l10n/l10n.dart';

class AppLocaleController {
  static final ValueNotifier<String> selectedTag = ValueNotifier<String>(
    AppSettings.appLocale.value,
  );

  static Locale? localeForTag(String tag) {
    if (tag.isEmpty) return null;
    for (final locale in L10n.supportedLocales) {
      if (locale.toLanguageTag() == tag) return locale;
    }
    return null;
  }

  static Future<void> setTag(String tag) async {
    final normalizedTag = localeForTag(tag)?.toLanguageTag() ?? '';
    await AppSettings.appLocale.setItem(normalizedTag);
    selectedTag.value = normalizedTag;
  }

  static String displayName(Locale locale) {
    final tag = locale.toLanguageTag();
    return _displayNames[tag] ?? tag;
  }

  static const _displayNames = <String, String>{
    'ar': 'العربية',
    'az': 'Azərbaycan dili',
    'be': 'Беларуская',
    'bn': 'বাংলা',
    'bo': 'བོད་ཡིག',
    'ca': 'Català',
    'cs': 'Čeština',
    'da': 'Dansk',
    'de': 'Deutsch',
    'el': 'Ελληνικά',
    'en': 'English',
    'eo': 'Esperanto',
    'es': 'Español',
    'et': 'Eesti',
    'eu': 'Euskara',
    'fa': 'فارسی',
    'fi': 'Suomi',
    'fil': 'Filipino',
    'fr': 'Français',
    'ga': 'Gaeilge',
    'gl': 'Galego',
    'he': 'עברית',
    'hi': 'हिन्दी',
    'hr': 'Hrvatski',
    'hu': 'Magyar',
    'ia': 'Interlingua',
    'id': 'Bahasa Indonesia',
    'ie': 'Interlingue',
    'it': 'Italiano',
    'ja': '日本語',
    'ka': 'ქართული',
    'kab': 'Taqbaylit',
    'ko': '한국어',
    'la': 'Latina',
    'lt': 'Lietuvių',
    'lv': 'Latviešu',
    'nb': 'Norsk bokmål',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'pt': 'Português',
    'pt-BR': 'Português (Brasil)',
    'pt-PT': 'Português (Portugal)',
    'ro': 'Română',
    'ru': 'Русский',
    'sk': 'Slovenčina',
    'sl': 'Slovenščina',
    'sq': 'Shqip',
    'sr': 'Српски',
    'sv': 'Svenska',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'th': 'ไทย',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'uz': 'Oʻzbekcha',
    'vi': 'Tiếng Việt',
    'yue-Hant': '粵語',
    'zh': '中文',
    'zh-Hant': '繁體中文',
  };
}
