// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'matrix_sdk_extensions/matrix_locals.dart';

// Weak keys retain formatted previews while their events are alive, including
// when a row scrolls out of the sliver and is later recreated.
final _previews = Expando<({Object key, String text})>();

bool _canUsePlainTextFastPath(Event event) {
  if (event.type != EventTypes.Message || event.redacted) return false;
  if (event.messageType != MessageTypes.Text &&
      event.messageType != MessageTypes.Notice &&
      event.messageType != MessageTypes.Emote &&
      event.messageType != MessageTypes.None) {
    return false;
  }

  final content = event.content;
  if (content['format'] == 'org.matrix.custom.html' ||
      event.relationshipType == RelationshipTypes.edit ||
      event.inReplyToEventId() != null) {
    return false;
  }

  final body = event.body;
  if (body.contains('\n') ||
      body.contains('\r') ||
      body.contains('\\') ||
      body.contains(String.fromCharCode(0x60)) ||
      body.contains('*') ||
      body.contains('_') ||
      body.contains('~') ||
      body.contains('[') ||
      body.contains('<') ||
      body.contains('&') ||
      body.contains('#') ||
      body.startsWith('> ') ||
      body.startsWith('- ') ||
      body.startsWith('+ ')) {
    return false;
  }

  var index = 0;
  while (index < body.length &&
      body.codeUnitAt(index) >= 0x30 &&
      body.codeUnitAt(index) <= 0x39) {
    index++;
  }
  if (index > 0 &&
      index + 1 < body.length &&
      (body.codeUnitAt(index) == 0x2e || body.codeUnitAt(index) == 0x29) &&
      body.codeUnitAt(index + 1) == 0x20) {
    return false;
  }
  return true;
}

String _formatPlainTextPreview(
  Event event,
  MatrixLocals locals, {
  required bool withSenderNamePrefix,
}) {
  var text = event.messageType == MessageTypes.Emote
      ? '* ${event.body}'
      : event.body;
  if (!withSenderNamePrefix) return text;

  final senderNameOrYou = event.senderId == event.room.client.userID
      ? locals.you
      : event.senderFromMemoryOrFallback.calcDisplayname(i18n: locals);
  text = '$senderNameOrYou: $text';
  return text;
}

String chatListPreviewText(
  Event event,
  MatrixLocals locals, {
  required bool withSenderNamePrefix,
}) {
  final plainTextFastPath = _canUsePlainTextFastPath(event);
  String format() => plainTextFastPath
      ? _formatPlainTextPreview(
          event,
          locals,
          withSenderNamePrefix: withSenderNamePrefix,
        )
      : event.calcLocalizedBodyFallback(
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

  final senderMember = event.room.getState(
    EventTypes.RoomMember,
    event.senderId,
  );
  final useCheapKey =
      plainTextFastPath &&
      (event.senderId == event.room.client.userID || senderMember != null);
  final Object key = useCheapKey
      ? (
          event.body,
          event.messageType,
          locals.l10n.localeName,
          withSenderNamePrefix,
          event.senderId,
          event.room.client.userID,
          senderMember?.content['displayname'],
          senderMember?.content['membership'],
        )
      : (
          // Complex messages keep the exhaustive invalidation path.
          jsonEncode(event.content),
          locals.l10n.localeName,
          withSenderNamePrefix,
          event.senderId,
          event.room.client.userID,
          (senderMember?.asUser(event.room) ??
                  User(event.senderId, room: event.room))
              .calcDisplayname(i18n: locals),
        );
  final cached = _previews[event];
  if (cached != null && cached.key == key) return cached.text;

  final text = format();
  _previews[event] = (key: key, text: text);
  return text;
}
