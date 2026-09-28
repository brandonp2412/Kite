// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_search_bar.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
