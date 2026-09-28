// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/utils/app_locale_controller.dart';
import 'package:kite/utils/kite_share.dart';
import 'package:kite/utils/platform_infos.dart';
import 'package:kite/widgets/avatar.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    final searching = controller.settingsSearch.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: controller.settingsSearchController,
                onChanged: controller.setSettingsSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search settings...',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: searching
                      ? IconButton(
                          tooltip: l10n.cancel,
                          onPressed: controller.clearSettingsSearch,
                          icon: const Icon(Icons.close_outlined),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            if (!searching)
              FutureBuilder<Profile>(
                future: controller.profileFuture,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  final avatar = profile?.avatarUrl;
                  final mxid = Matrix.of(context).client.userID ?? l10n.user;
                  final displayname =
                      profile?.displayName ?? mxid.localpart ?? mxid;
                  return Column(
                    crossAxisAlignment: .center,
                    mainAxisSize: .min,
                    children: [
                      Stack(
                        children: [
                          Avatar(
                            mxContent: avatar,
                            name: displayname,
                            size: Avatar.defaultSize * 2.5,
                            onTap: avatar != null
                                ? () => showDialog(
                                    context: context,
                                    builder: (_) => MxcImageViewer(avatar),
                                  )
                                : null,
                          ),
                          if (profile != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: FloatingActionButton.small(
                                elevation: 2,
                                onPressed: controller.setAvatarAction,
                                heroTag: null,
                                child: const Icon(Icons.camera_alt_outlined),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: controller.setDisplaynameAction,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          iconColor: theme.colorScheme.onSurface,
                        ),
                        label: Text(
                          displayname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      TextButton(
                        onPressed: () => FluffyShare.share(mxid, context),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.secondary,
                          iconColor: theme.colorScheme.secondary,
                        ),
                        child: Text(
                          mxid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            if (controller.settingsMatches([
              l10n.chatBackup,
              'backup',
              'recovery',
            ]))
              SwitchListTile.adaptive(
                controlAffinity: ListTileControlAffinity.trailing,
                value: controller.cryptoIdentityConnected == true,
                secondary: const Icon(Icons.backup_outlined),
                title: Text(l10n.chatBackup),
                onChanged: controller.firstRunBootstrapAction,
                contentPadding: const EdgeInsets.only(left: 16, right: 8),
              ),
            if (controller.settingsMatches([l10n.manageAccount, 'account']))
              FutureBuilder(
                future: Result.capture(
                  Matrix.of(context).client.getAuthMetadata(),
                ).then((result) => result.asValue?.value),
                builder: (context, snapshot) {
                  final accountManageUrl = snapshot.data?.accountManagementUri;
                  if (accountManageUrl == null) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(l10n.manageAccount),
                    trailing: const Icon(Icons.open_in_new_outlined),
                    onTap: () => launchUrl(
                      accountManageUrl,
                      mode: LaunchMode.inAppBrowserView,
                    ),
                  );
                },
              ),
            if (controller.settingsMatches([
              l10n.changeTheme,
              'theme',
              'appearance',
              'colour',
              'color',
            ]))
              ListTile(
                leading: const Icon(Icons.format_paint_outlined),
                title: Text(l10n.changeTheme),
                tileColor: activeRoute.startsWith('/rooms/settings/style')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
                onTap: () => context.go('/rooms/settings/style'),
              ),
            if (controller.settingsMatches([
              l10n.language,
              'locale',
              'translation',
            ]))
              ValueListenableBuilder<String>(
                valueListenable: AppLocaleController.selectedTag,
                builder: (context, localeTag, _) => ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: Text(l10n.language),
                  subtitle: Text(
                    localeTag.isEmpty
                        ? l10n.systemDefault
                        : AppLocaleController.displayName(
                            AppLocaleController.localeForTag(localeTag) ??
                                Localizations.localeOf(context),
                          ),
                  ),
                  onTap: controller.setLanguageAction,
                ),
              ),
            if (controller.settingsMatches([
              l10n.notifications,
              'notification',
              'push',
            ]))
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(l10n.notifications),
                tileColor:
                    activeRoute.startsWith('/rooms/settings/notifications')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
                onTap: () => context.go('/rooms/settings/notifications'),
              ),
            if (controller.settingsMatches([l10n.devices, 'device', 'session']))
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(l10n.devices),
                onTap: () => context.go('/rooms/settings/devices'),
                tileColor: activeRoute.startsWith('/rooms/settings/devices')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
              ),
            if (controller.settingsMatches([l10n.chat, 'message', 'composer']))
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(l10n.chat),
                onTap: () => context.go('/rooms/settings/chat'),
                tileColor: activeRoute.startsWith('/rooms/settings/chat')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
              ),
            if (controller.settingsMatches([
              l10n.security,
              'security',
              'encryption',
              'keys',
            ]))
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.security),
                onTap: () => context.go('/rooms/settings/security'),
                tileColor: activeRoute.startsWith('/rooms/settings/security')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
              ),
            if (!searching) Divider(color: theme.dividerColor),
            if (controller.settingsMatches([
              l10n.aboutHomeserver(
                Matrix.of(context).client.userID?.domain ?? 'homeserver',
              ),
              'homeserver',
              'server',
            ]))
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(
                  l10n.aboutHomeserver(
                    Matrix.of(context).client.userID?.domain ?? 'homeserver',
                  ),
                ),
                onTap: () => context.go('/rooms/settings/homeserver'),
                tileColor: activeRoute.startsWith('/rooms/settings/homeserver')
                    ? theme.colorScheme.surfaceContainerHigh
                    : null,
              ),
            if (controller.settingsMatches([l10n.privacy, 'privacy', 'policy']))
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(l10n.privacy),
                onTap: () => launchUrlString(AppSettings.privacyPolicy.value),
              ),
            if (controller.settingsMatches([
              l10n.about,
              'about',
              'version',
              'license',
            ]))
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.about),
                onTap: () => PlatformInfos.showDialog(context),
              ),
            if (!searching) Divider(color: theme.dividerColor),
            if (controller.settingsMatches([l10n.logout, 'logout', 'sign out']))
              ListTile(
                leading: const Icon(Icons.logout_outlined),
                title: Text(l10n.logout),
                onTap: controller.logoutAction,
              ),
          ],
        ),
      ),
    );
  }
}
