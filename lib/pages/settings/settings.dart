// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/utils/app_locale_controller.dart';
import 'package:kite/utils/file_selector.dart';
import 'package:kite/utils/platform_infos.dart';
import 'package:kite/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:kite/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:kite/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:kite/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;
  final settingsSearchController = TextEditingController();
  String settingsSearch = '';

  void setSettingsSearch(String value) => setState(() {
    settingsSearch = value.trim().toLowerCase();
  });

  void clearSettingsSearch() {
    settingsSearchController.clear();
    setState(() => settingsSearch = '');
  }

  bool settingsMatches(Iterable<String> values) =>
      settingsSearch.isEmpty ||
      values.any((value) => value.toLowerCase().contains(settingsSearch));

  void updateProfile() => setState(() {
    profileUpdated = true;
    profileFuture = null;
  });

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: profile?.displayName ?? matrix.client.userID!.localpart,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  Future<void> setLanguageAction() async {
    final l10n = L10n.of(context);
    final currentTag = AppLocaleController.selectedTag.value;
    final selectedTag = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            children: [
              ListTile(
                title: Text(l10n.language),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone_android_outlined),
                      title: Text(l10n.systemDefault),
                      trailing: currentTag.isEmpty
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(''),
                    ),
                    for (final locale in L10n.supportedLocales)
                      ListTile(
                        title: Text(AppLocaleController.displayName(locale)),
                        subtitle: Text(locale.toLanguageTag()),
                        trailing: currentTag == locale.toLanguageTag()
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(locale.toLanguageTag()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selectedTag == null) return;
    await AppLocaleController.setTag(selectedTag);
    if (mounted) setState(() {});
  }

  Future<void> logoutAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final consent = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.areYouSureYouWantToLogout,
      message: l10n.noBackupWarning,
      isDestructive: cryptoIdentityConnected == false,
      okLabel: l10n.logout,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
    if (!mounted) return;
    context.go('/');
  }

  Future<void> setAvatarAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: l10n.openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: l10n.openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: l10n.removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: l10n.changeYourAvatar,
            cancelLabel: l10n.cancel,
            actions: actions,
          );
    if (action == null) return;
    if (!mounted) return;
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  Future<void> checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    if (!client.isLogged()) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    final state = await client.getCryptoIdentityState();
    if (!mounted) return;
    setState(() {
      cryptoIdentityConnected = state.initialized && state.connected;
    });
  }

  bool? cryptoIdentityConnected;

  Future<void> firstRunBootstrapAction([_]) async {
    if (cryptoIdentityConnected == true) {
      final action = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).resetRecoveryKey,
        cancelLabel: L10n.of(context).close,
        isDestructive: true,
      );
      if (action != OkCancelResult.ok) return;
      if (!mounted) return;
      await context.push('/backup?reset=true');
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  @override
  void dispose() {
    settingsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(client.userID!);
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
