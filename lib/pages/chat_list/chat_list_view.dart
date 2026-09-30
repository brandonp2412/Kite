// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:kite/config/themes.dart';
import 'package:kite/pages/chat_list/chat_list.dart';
import 'package:kite/pages/chat_list/chat_list_search_bar.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';
import 'package:kite/utils/stream_extension.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusBarStyle =
        theme.appBarTheme.systemOverlayStyle?.copyWith(
          statusBarColor: Colors.transparent,
          systemStatusBarContrastEnforced: false,
        ) ??
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness,
          systemStatusBarContrastEnforced: false,
        );
    final columnMode = FluffyThemes.isColumnMode(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusBarStyle,
      child: PopScope(
        canPop: !controller.isSearchMode,
        onPopInvokedWithResult: (pop, _) {
          if (pop) return;
          if (controller.isSearchMode) {
            controller.cancelSearch();
          }
        },
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 8,
            ),
            child: Stack(
              children: [
                Positioned.fill(child: ChatListViewBody(controller)),
                _PinnedChatsShelf(
                  controller: controller,
                  bottom: columnMode ? 0 : bottomInset + 88,
                ),
                if (!columnMode)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: bottomInset + 16,
                    child: Material(
                      elevation: 8,
                      shadowColor: theme.colorScheme.shadow.withValues(
                        alpha: 0.24,
                      ),
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(99),
                      clipBehavior: Clip.antiAlias,
                      child: ChatListSearchBar(controller: controller),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedChatsShelf extends StatelessWidget {
  final ChatListController controller;
  final double bottom;

  const _PinnedChatsShelf({required this.controller, required this.bottom});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;

    return StreamBuilder(
      stream: client.onSync.stream
          .where((sync) => sync.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        if (controller.isSearchMode) return const SizedBox.shrink();

        final rooms = controller.filteredRooms
            .where((room) => room.isFavourite)
            .toList();
        if (rooms.isEmpty) return const SizedBox.shrink();

        final height = pinnedChatsShelfHeight(context, rooms.length);
        final theme = Theme.of(context);

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          height: height,
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 8,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.18),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return ChatListItem(
                  room,
                  key: Key('pinned_chat_list_item_${room.id}'),
                  onTap: () => controller.onChatTap(room),
                  onLongPress: (context) =>
                      controller.chatContextAction(room, context),
                  activeChat: controller.activeChat == room.id,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
