// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:kite/config/setting_keys.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/pages/chat/events/poll.dart';
import 'package:kite/pages/chat/events/video_player.dart';
import 'package:kite/pages/image_viewer/image_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';
import '../../../utils/event_checkbox_extension.dart';
import '../../../utils/platform_infos.dart';
import '../../../utils/url_launcher.dart';
import 'audio_player.dart';
import 'cute_events.dart';
import 'html_message.dart';
import 'image_bubble.dart';
import 'map_bubble.dart';
import 'message_download_content.dart';

class MessageContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;
  final void Function(Event)? onInfoTab;
  final BorderRadius borderRadius;
  final Timeline timeline;
  final bool selected;
  final Set<String> bigEmojis;

  const MessageContent(
    this.event, {
    this.onInfoTab,
    super.key,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    required this.borderRadius,
    required this.selected,
    required this.bigEmojis,
  });

  @override
  Widget build(BuildContext context) {
    const fontSize = AppConfig.messageFontSize;
    final buttonTextColor = textColor;
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
      case EventTypes.Sticker:
        switch (event.messageType) {
          case MessageTypes.Image:
          case MessageTypes.Sticker:
            if (event.redacted) continue textmessage;
            final maxSize = event.messageType == MessageTypes.Sticker
                ? 128.0
                : 256.0;
            final w = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('w');
            final h = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('h');
            var width = maxSize;
            var height = maxSize;
            var fit = event.messageType == MessageTypes.Sticker
                ? BoxFit.contain
                : BoxFit.cover;
            if (w != null && h != null) {
              fit = BoxFit.contain;
              if (w > h) {
                width = maxSize;
                height = max(32, maxSize * (h / w));
              } else {
                height = maxSize;
                width = max(32, maxSize * (w / h));
              }
            }
            return ImageBubble(
              event,
              width: width,
              height: height,
              fit: fit,
              borderRadius: borderRadius,
              timeline: timeline,
              textColor: textColor,
              onTap: () => showDialog(
                context: context,
                builder: (_) => ImageViewer(
                  event,
                  timeline: timeline,
                  outerContext: context,
                ),
              ),
            );
          case CuteEventContent.eventType:
            return CuteContent(event);
          case MessageTypes.Audio:
            if (PlatformInfos.isMobile ||
                PlatformInfos.isMacOS ||
                PlatformInfos.isWeb ||
                PlatformInfos.isLinux) {
              return AudioPlayerWidget(
                event,
                color: textColor,
                linkColor: linkColor,
                fontSize: fontSize,
              );
            }
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.Video:
            return EventVideoPlayer(
              event,
              textColor: textColor,
              linkColor: linkColor,
              timeline: timeline,
            );
          case MessageTypes.File:
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.Location:
            final geoUri = Uri.tryParse(
              event.content.tryGet<String>('geo_uri')!,
            );
            if (geoUri != null && geoUri.scheme == 'geo') {
              final latlong = geoUri.path
                  .split(';')
                  .first
                  .split(',')
                  .map(double.tryParse)
                  .toList();
              if (latlong.length == 2 &&
                  latlong.first != null &&
                  latlong.last != null) {
                return MapBubble(
                  onTap: () =>
                      UrlLauncher(context, geoUri.toString()).launchUrl(),
                  latitude: latlong.first!,
                  longitude: latlong.last!,
                );
              }
            }
            continue textmessage;
          case MessageTypes.Text:
          case MessageTypes.Notice:
          case MessageTypes.Emote:
          case MessageTypes.None:
          textmessage:
          default:
            if (event.redacted) {
              return RedactionWidget(
                event: event,
                buttonTextColor: buttonTextColor,
                onInfoTab: onInfoTab,
                fontSize: fontSize,
              );
            }
            var html = AppSettings.renderHtml.value && event.isRichMessage
                ? event.formattedText
                : event.body.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            if (event.messageType == MessageTypes.Emote) {
              html = '* $html';
            }

            final bigEmotes =
                !event.isRichMessage && bigEmojis.contains(event.body);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _CachedHtmlMessage(
                html: html,
                textColor: textColor,
                linkColor: linkColor,
                room: event.room,
                fontSize: AppConfig.messageFontSize * (bigEmotes ? 5 : 1),
                eventId: event.eventId,
                checkboxCheckedEvents: event.aggregatedEvents(
                  timeline,
                  EventCheckboxRoomExtension.relationshipType,
                ),
                messagePreviewMaxLines:
                    AppSettings.messagePreviewMaxLines.value,
              ),
            );
        }
      case PollEventContent.startType:
        if (event.redacted) {
          return RedactionWidget(
            event: event,
            buttonTextColor: buttonTextColor,
            onInfoTab: onInfoTab,
            fontSize: fontSize,
          );
        }
        return PollWidget(
          event: event,
          timeline: timeline,
          textColor: textColor,
          linkColor: linkColor,
        );
      case EventTypes.CallInvite:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).startedACall(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
              ),
              icon: '📞',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
      default:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).userSentUnknownEvent(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                event.type,
              ),
              icon: 'ℹ️',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
    }
  }
}

class _CachedHtmlMessage extends StatefulWidget {
  const _CachedHtmlMessage({
    required this.html,
    required this.textColor,
    required this.linkColor,
    required this.room,
    required this.fontSize,
    required this.eventId,
    required this.checkboxCheckedEvents,
    required this.messagePreviewMaxLines,
  });

  final String html;
  final Color textColor;
  final Color linkColor;
  final Room room;
  final double fontSize;
  final String eventId;
  final Set<Event> checkboxCheckedEvents;
  final int messagePreviewMaxLines;

  @override
  State<_CachedHtmlMessage> createState() => _CachedHtmlMessageState();
}

class _CachedHtmlMessageState extends State<_CachedHtmlMessage> {
  late Widget _child;
  late String _html;
  late Color _textColor;
  late Color _linkColor;
  late Room _room;
  late double _fontSize;
  late String _eventId;
  late int _messagePreviewMaxLines;
  late List<(String, int?, String)> _checkboxSnapshot;

  List<(String, int?, String)> _snapshotCheckboxes() {
    final snapshot = widget.checkboxCheckedEvents
        .map(
          (event) => (event.eventId, event.checkedCheckboxId, event.senderId),
        )
        .toList();
    snapshot.sort((a, b) {
      final eventIdComparison = a.$1.compareTo(b.$1);
      if (eventIdComparison != 0) return eventIdComparison;
      final checkboxComparison = (a.$2 ?? -1).compareTo(b.$2 ?? -1);
      if (checkboxComparison != 0) return checkboxComparison;
      return a.$3.compareTo(b.$3);
    });
    return snapshot;
  }

  bool _sameCheckboxSnapshot(List<(String, int?, String)> next) {
    if (_checkboxSnapshot.length != next.length) return false;
    for (var index = 0; index < next.length; index++) {
      if (_checkboxSnapshot[index] != next[index]) return false;
    }
    return true;
  }

  void _refreshChild() {
    _html = widget.html;
    _textColor = widget.textColor;
    _linkColor = widget.linkColor;
    _room = widget.room;
    _fontSize = widget.fontSize;
    _eventId = widget.eventId;
    _messagePreviewMaxLines = widget.messagePreviewMaxLines;
    _checkboxSnapshot = _snapshotCheckboxes();
    _child = HtmlMessage(
      html: widget.html,
      textColor: widget.textColor,
      room: widget.room,
      fontSize: widget.fontSize,
      linkStyle: TextStyle(
        color: widget.linkColor,
        fontSize: AppConfig.messageFontSize,
        decoration: TextDecoration.underline,
        decorationColor: widget.linkColor,
      ),
      onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
      eventId: widget.eventId,
      checkboxCheckedEvents: widget.checkboxCheckedEvents,
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshChild();
  }

  @override
  void didUpdateWidget(covariant _CachedHtmlMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final checkboxSnapshot = _snapshotCheckboxes();
    if (_html != widget.html ||
        _textColor != widget.textColor ||
        _linkColor != widget.linkColor ||
        !identical(_room, widget.room) ||
        _fontSize != widget.fontSize ||
        _eventId != widget.eventId ||
        _messagePreviewMaxLines != widget.messagePreviewMaxLines ||
        !_sameCheckboxSnapshot(checkboxSnapshot)) {
      _refreshChild();
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}

class RedactionWidget extends StatelessWidget {
  const RedactionWidget({
    super.key,
    required this.event,
    required this.buttonTextColor,
    required this.onInfoTab,
    required this.fontSize,
  });

  final Event event;
  final Color buttonTextColor;
  final void Function(Event p1)? onInfoTab;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: event.redactedBecause?.fetchSenderUser(),
      builder: (context, snapshot) {
        final reason = event.redactedBecause?.content.tryGet<String>('reason');
        final redactedBy =
            snapshot.data?.calcDisplayname() ??
            event.redactedBecause?.senderId.localpart ??
            L10n.of(context).user;
        return _ButtonContent(
          label: reason == null
              ? L10n.of(context).redactedBy(redactedBy)
              : L10n.of(context).redactedByBecause(redactedBy, reason),
          icon: '🗑️',
          textColor: buttonTextColor.withAlpha(128),
          onPressed: () => onInfoTab!(event),
          fontSize: fontSize,
        );
      },
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final void Function() onPressed;
  final String label;
  final String icon;
  final Color? textColor;
  final double fontSize;

  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.textColor,
    required this.onPressed,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onPressed,
        child: Text(
          '$icon  $label',
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
      ),
    );
  }
}
