// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ClientChooserButton extends StatelessWidget {
  const ClientChooserButton({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return FutureBuilder<Profile>(
      future: client.isLogged() ? client.fetchOwnProfile() : null,
      builder: (context, snapshot) => IconButton(
        key: const Key('account_settings_button'),
        tooltip: L10n.of(context).settings,
        onPressed: () => context.go('/rooms/settings'),
        icon: Avatar(
          mxContent: snapshot.data?.avatarUrl,
          name: snapshot.data?.displayName ?? client.userID?.localpart,
          size: 32,
        ),
      ),
    );
  }
}
