// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:kite/config/themes.dart';
import 'package:kite/widgets/avatar.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SeenByRow extends StatefulWidget {
  final Event event;
  const SeenByRow({super.key, required this.event});

  @override
  State<SeenByRow> createState() => _SeenByRowState();
}

class _SeenByRowState extends State<SeenByRow> {
  static const _maxAvatars = 7;

  List<(String, Uri?, String)>? _cachedUsers;
  Color? _cachedSurfaceColor;
  Widget? _cachedAvatars;

  bool _sameUsers(
    List<(String, Uri?, String)> previous,
    List<(String, Uri?, String)> current,
  ) {
    if (previous.length != current.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (previous[index] != current[index]) return false;
    }
    return true;
  }

  Widget _buildAvatars(List<User> users, Color surfaceColor) {
    final snapshot = [
      for (final user in users)
        (user.id, user.avatarUrl, user.calcDisplayname()),
    ];
    final cachedUsers = _cachedUsers;
    final cachedAvatars = _cachedAvatars;
    if (cachedUsers != null &&
        cachedAvatars != null &&
        _cachedSurfaceColor == surfaceColor &&
        _sameUsers(cachedUsers, snapshot)) {
      return cachedAvatars;
    }

    final visibleUsers = snapshot.length > _maxAvatars
        ? snapshot.sublist(0, _maxAvatars)
        : snapshot;
    final avatars = Wrap(
      spacing: 4,
      children: [
        for (final user in visibleUsers)
          Avatar(mxContent: user.$2, name: user.$3, size: 16),
        if (snapshot.length > _maxAvatars)
          SizedBox(
            width: 16,
            height: 16,
            child: Material(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(32),
              child: Center(
                child: Text(
                  '+${snapshot.length - _maxAvatars}',
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
          ),
      ],
    );
    _cachedUsers = snapshot;
    _cachedSurfaceColor = surfaceColor;
    _cachedAvatars = avatars;
    return avatars;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final theme = Theme.of(context);

    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[event.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, asyncSnapshot) {
        final seenByUsers = event.receipts
            .map((receipt) => receipt.user)
            .where(
              (user) =>
                  user.id != event.room.client.userID &&
                  user.id != event.senderId,
            )
            .toList();
        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            height: seenByUsers.isEmpty ? 0 : 24,
            duration: seenByUsers.isEmpty
                ? Duration.zero
                : FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment: event.senderId == Matrix.of(context).client.userID
                ? Alignment.topRight
                : Alignment.topLeft,
            padding: const EdgeInsets.only(
              bottom: 4,
              top: 1,
              left: 8,
              right: 8,
            ),
            child: _buildAvatars(seenByUsers, theme.colorScheme.surface),
          ),
        );
      },
    );
  }
}
