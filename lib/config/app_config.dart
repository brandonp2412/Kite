// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF261386);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'app.kite://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'kite_push';
  static const String pushNotificationsAppId = 'app.kite';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String enablePushTutorial =
      'https://brandonp2412.github.io/Kite/support/';
  static const String encryptionTutorial =
      'https://brandonp2412.github.io/Kite/support/';
  static const String howDoIGetStickersTutorial =
      'https://brandonp2412.github.io/Kite/support/';
  static const String appId = 'app.kite';
  static const String appOpenUrlScheme = 'app.kite';
  static const String appSsoUrlScheme = 'app.kite.auth';

  static const String sourceCodeUrl = 'https://github.com/brandonp2412/Kite';
  static const String supportUrl =
      'https://brandonp2412.github.io/Kite/support/';
  static const String changelogUrl =
      'https://github.com/brandonp2412/Kite/releases';
  static const String helpUrl = 'https://brandonp2412.github.io/Kite/support/';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/brandonp2412/Kite/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    path: 'brandonp2412/Kite/refs/heads/main/recommended_homeservers.json',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.8.1';
}
