// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'matrix_sdk_extensions/matrix_locals.dart';

// Weak keys retain formatted previews while their events are alive, including
// when a row scrolls out of the sliver and is later recreated.
final _previews = Expando<({Object key, String text})>();

String chatListPreviewText(
  Event event,
  MatrixLocals locals, {
  required bool withSenderNamePrefix,
}) {
  String format() => event.calcLocalizedBodyFallback(
    locals,
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
    removeMarkdown: true,
    withSenderNamePrefix: withSenderNamePrefix,
  );

  // State events and redactions can depend on other room state. Keep their
  // localization live; cache the ordinary message previews that dominate rows.
  if (event.type != EventTypes.Message || event.redacted) return format();

  final key = (
    // Content maps can be edited in place, so object identity is insufficient.
    jsonEncode(event.content),
    locals.l10n.localeName,
    withSenderNamePrefix,
    event.senderId,
    event.room.client.userID,
    (event.room
                .getState(EventTypes.RoomMember, event.senderId)
                ?.asUser(event.room) ??
            User(event.senderId, room: event.room))
        .calcDisplayname(i18n: locals),
  );
  final cached = _previews[event];
  if (cached != null && cached.key == key) return cached.text;

  final text = format();
  _previews[event] = (key: key, text: text);
  return text;
}
