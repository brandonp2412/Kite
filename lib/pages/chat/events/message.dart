// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/services.dart';
import 'package:kite/config/setting_keys.dart';
import 'package:kite/config/themes.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/utils/adaptive_bottom_sheet.dart';
import 'package:kite/utils/date_time_extension.dart';
import 'package:kite/utils/file_description.dart';
import 'package:kite/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:kite/utils/string_color.dart';
import 'package:kite/widgets/avatar.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:kite/widgets/member_actions_popup_menu_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

import '../../../config/app_config.dart';
import '../sticker_picker_dialog.dart';
import 'message_content.dart';
import 'message_reactions.dart';
import 'reply_content.dart';
import 'state_message.dart';

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final void Function(Event) onSelect;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function() onMention;
  final void Function() onEdit;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;
  final bool animateIn;
  final bool wallpaperMode;
  final ScrollController scrollController;
  final List<Color> colors;
  final void Function()? onExpand;
  final bool isCollapsed;
  final Set<String> bigEmojis;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.longPressSelect = false,
    required this.bigEmojis,
    required this.onSelect,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onSwipe,
    this.selected = false,
    required this.onEdit,
    required this.singleSelected,
    required this.timeline,
    this.highlightMarker = false,
    this.animateIn = false,
    this.wallpaperMode = false,
    required this.onMention,
    required this.scrollController,
    required this.colors,
    this.onExpand,
    required this.enterThread,
    this.isCollapsed = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!{
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.CallInvite,
      PollEventContent.startType,
    }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      return StateMessage(event, onExpand: onExpand, isCollapsed: isCollapsed);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return StateMessage(event);
    }

    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    final alignment = ownMessage ? Alignment.topRight : Alignment.topLeft;

    var color = theme.colorScheme.surfaceContainerHigh;
    final displayTime =
        event.type == EventTypes.RoomCreate ||
        previousEvent == null ||
        !event.originServerTs.sameEnvironment(previousEvent!.originServerTs);

    final nextEventSameSender =
        nextEvent != null &&
        {EventTypes.Message, EventTypes.Sticker}.contains(nextEvent!.type) &&
        nextEvent!.senderId == event.senderId &&
        nextEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final previousEventSameSender =
        previousEvent != null &&
        {
          EventTypes.Message,
          EventTypes.Sticker,
        }.contains(previousEvent!.type) &&
        previousEvent!.senderId == event.senderId &&
        previousEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final textColor = ownMessage
        ? theme.onBubbleColor
        : theme.colorScheme.onSurface;

    final linkColor = ownMessage
        ? theme.brightness == Brightness.light
              ? theme.colorScheme.primaryFixed
              : theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.primary;

    final rowMainAxisAlignment = ownMessage
        ? MainAxisAlignment.end
        : MainAxisAlignment.start;

    final displayEvent = event.getDisplayEvent(timeline);
    const hardCorner = Radius.circular(3);
    const roundedCorner = Radius.circular(AppConfig.borderRadius);
    final borderRadius = BorderRadius.only(
      topLeft: !ownMessage ? hardCorner : roundedCorner,
      topRight: ownMessage && nextEventSameSender ? hardCorner : roundedCorner,
      bottomLeft: !ownMessage && previousEventSameSender
          ? hardCorner
          : roundedCorner,
      bottomRight: ownMessage ? hardCorner : roundedCorner,
    );
    const avatarSize = Avatar.defaultSize;
    final noBubble =
        ({
          MessageTypes.Video,
          MessageTypes.Image,
          MessageTypes.Sticker,
        }.contains(event.messageType) &&
        event.fileDescription == null &&
        !event.redacted);

    if (ownMessage) {
      color = displayEvent.status.isError
          ? Colors.redAccent
          : theme.bubbleColor;
    }

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where(
              (event) =>
                  event.senderId == event.room.client.userID &&
                  event.type == 'm.reaction',
            )
            .map(
              (event) => event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );

    final isEdited = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.edit,
    );

    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;

    final enterThread = this.enterThread;
    final sender = event.senderFromMemoryOrFallback;

    final wallpaperTextShadow = !wallpaperMode
        ? null
        : [
            Shadow(
              offset: Offset(0.0, 0.0),
              blurRadius: 2,
              color: theme.colorScheme.surface,
            ),
          ];
    return Center(
      child: Swipeable(
        key: ValueKey(event.transactionId ?? event.eventId),
        background: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0),
          child: Center(child: Icon(Icons.check_outlined)),
        ),
        direction: AppSettings.swipeRightToLeftToReply.value
            ? SwipeDirection.endToStart
            : SwipeDirection.startToEnd,
        onSwipe: (_) => onSwipe(),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: nextEventSameSender ? 1.0 : 8.0,
            bottom: previousEventSameSender || previousEvent == null
                ? 1.0
                : 8.0,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: ownMessage ? .end : .start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: InkWell(
                      hoverColor: longPressSelect ? Colors.transparent : null,
                      enableFeedback: !selected,
                      onTap: longPressSelect ? null : () => onSelect(event),
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius / 2,
                      ),
                      child: Material(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 2,
                        ),
                        color: selected || highlightMarker
                            ? theme.colorScheme.secondaryContainer.withAlpha(
                                128,
                              )
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: .start,
                    mainAxisAlignment: rowMainAxisAlignment,
                    children: [
                      if (longPressSelect && !event.redacted)
                        SizedBox(
                          height: avatarSize,
                          width: avatarSize,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: L10n.of(context).select,
                            icon: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                            onPressed: () => onSelect(event),
                          ),
                        )
                      else if (nextEventSameSender || ownMessage)
                        SizedBox(width: avatarSize)
                      else
                        FutureBuilder<User?>(
                          future: event.fetchSenderUser(),
                          builder: (context, snapshot) {
                            final user = snapshot.data ?? sender;
                            return Avatar(
                              mxContent: user.avatarUrl,
                              name: user.calcDisplayname(),
                              onTap: () => showMemberActionsPopupMenu(
                                context: context,
                                user: user,
                                onMention: onMention,
                              ),
                              size: avatarSize,
                              presenceUserId: user.stateKey,
                              presenceBackgroundColor: wallpaperMode
                                  ? Colors.transparent
                                  : null,
                            );
                          },
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          mainAxisSize: .min,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 8.0),
                              child: Row(
                                mainAxisAlignment: ownMessage ? .end : .start,
                                children: [
                                  if ((!nextEventSameSender) && !ownMessage)
                                    FutureBuilder<User?>(
                                      future: event.fetchSenderUser(),
                                      builder: (context, snapshot) {
                                        final displayname =
                                            snapshot.data?.calcDisplayname() ??
                                            sender.calcDisplayname();
                                        return ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: 200,
                                          ),
                                          child: Text(
                                            displayname,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: event.room.isDirectChat
                                                  ? Colors.transparent
                                                  : (theme.brightness ==
                                                            Brightness.light
                                                        ? displayname
                                                              .colorScheme
                                                              .primary
                                                        : displayname
                                                              .colorScheme
                                                              .primaryContainer),
                                              fontSize: 11,
                                              shadows: event.room.isDirectChat
                                                  ? null
                                                  : wallpaperTextShadow,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),

                            Container(
                              alignment: alignment,
                              padding: const EdgeInsets.only(left: 8),
                              child: GestureDetector(
                                onDoubleTap:
                                    AppSettings.doubleTapToReact.value &&
                                        event.room.canSendDefaultMessages
                                    ? () {
                                        HapticFeedback.lightImpact();
                                        final emoji =
                                            AppSettings.doubleTapReaction.value;
                                        final existingReaction = event
                                            .aggregatedEvents(
                                              timeline,
                                              RelationshipTypes.reaction,
                                            )
                                            .firstWhereOrNull(
                                              (e) =>
                                                  e.senderId ==
                                                      event
                                                          .room
                                                          .client
                                                          .userID &&
                                                  e.content
                                                          .tryGetMap<
                                                            String,
                                                            Object?
                                                          >('m.relates_to')
                                                          ?.tryGet<String>(
                                                            'key',
                                                          ) ==
                                                      emoji,
                                            );
                                        if (existingReaction != null) {
                                          existingReaction.redactEvent();
                                        } else {
                                          event.room.sendReaction(
                                            event.eventId,
                                            emoji,
                                          );
                                        }
                                      }
                                    : null,
                                onLongPress: longPressSelect
                                    ? null
                                    : () {
                                        HapticFeedback.heavyImpact();
                                        onSelect(event);
                                      },
                                child: _AnimateIn(
                                  key: ValueKey(
                                    event.transactionId ?? event.eventId,
                                  ),
                                  animateIn: animateIn,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: noBubble
                                          ? Colors.transparent
                                          : color,
                                      borderRadius: borderRadius,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: BubbleBackground(
                                      colors: colors,
                                      ignore:
                                          noBubble ||
                                          !ownMessage ||
                                          MediaQuery.highContrastOf(context),
                                      scrollController: scrollController,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                        ),
                                        constraints: const BoxConstraints(
                                          maxWidth:
                                              FluffyThemes.columnWidth * 1.5,
                                        ),
                                        child: Column(
                                          mainAxisSize: .min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            if (event.inReplyToEventId(
                                                  includingFallback: false,
                                                ) !=
                                                null)
                                              FutureBuilder<Event?>(
                                                future: event.getReplyEvent(
                                                  timeline,
                                                ),
                                                builder: (BuildContext context, snapshot) {
                                                  final replyEvent =
                                                      snapshot.hasData
                                                      ? snapshot.data!
                                                      : Event(
                                                          eventId:
                                                              event
                                                                  .inReplyToEventId() ??
                                                              '\$fake_event_id',
                                                          content: {
                                                            'msgtype': 'm.text',
                                                            'body': '...',
                                                          },
                                                          senderId:
                                                              event.senderId,
                                                          type:
                                                              'm.room.message',
                                                          room: event.room,
                                                          status:
                                                              EventStatus.sent,
                                                          originServerTs:
                                                              DateTime.now(),
                                                        );
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 16,
                                                          right: 16,
                                                          top: 8,
                                                        ),
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      borderRadius: ReplyContent
                                                          .borderRadius,
                                                      child: InkWell(
                                                        borderRadius:
                                                            ReplyContent
                                                                .borderRadius,
                                                        onTap: () =>
                                                            scrollToEventId(
                                                              replyEvent
                                                                  .eventId,
                                                            ),
                                                        child: AbsorbPointer(
                                                          child: ReplyContent(
                                                            replyEvent,
                                                            ownMessage:
                                                                ownMessage,
                                                            timeline: timeline,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            MessageContent(
                                              displayEvent,
                                              textColor: textColor,
                                              linkColor: linkColor,
                                              onInfoTab: onInfoTab,
                                              borderRadius: borderRadius,
                                              timeline: timeline,
                                              selected: selected,
                                              bigEmojis: bigEmojis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            AnimatedSize(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              alignment: Alignment.bottomCenter,
                              child: !hasReactions
                                  ? const SizedBox.shrink()
                                  : Container(
                                      alignment: ownMessage
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      padding: EdgeInsets.only(
                                        top: 1.0,
                                        left: 8.0,
                                        right: ownMessage ? 0 : 12.0,
                                      ),
                                      child: MessageReactions(event, timeline),
                                    ),
                            ),
                            _MessageStatusMetadata(
                              event: event,
                              ownMessage: ownMessage,
                              showTime:
                                  displayTime ||
                                  !previousEventSameSender ||
                                  selected,
                              detailedTime: selected,
                              isEdited: isEdited,
                              textColor: theme.colorScheme.onSurface,
                              errorColor: theme.colorScheme.error,
                              shadowColor: wallpaperMode
                                  ? theme.colorScheme.surface
                                  : null,
                            ),
                            Align(
                              alignment: ownMessage
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: FluffyThemes.animationDuration,
                                curve: FluffyThemes.animationCurve,
                                child: showReactionPicker
                                    ? Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Material(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHigh,
                                          shape: StadiumBorder(
                                            side: BorderSide(
                                              color: theme
                                                  .colorScheme
                                                  .outlineVariant,
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisSize: .min,
                                              children: [
                                                ...AppConfig.defaultReactions.map(
                                                  (emoji) => Padding(
                                                    padding:
                                                        const EdgeInsets.all(2),
                                                    child: IconButton(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      style: IconButton.styleFrom(
                                                        backgroundColor:
                                                            sentReactions
                                                                .contains(emoji)
                                                            ? theme
                                                                  .colorScheme
                                                                  .primaryContainer
                                                            : Colors
                                                                  .transparent,
                                                        minimumSize: const Size(
                                                          38,
                                                          38,
                                                        ),
                                                      ),
                                                      icon: Text(
                                                        emoji,
                                                        style: const TextStyle(
                                                          fontSize: 20,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      onPressed:
                                                          sentReactions
                                                              .contains(emoji)
                                                          ? null
                                                          : () {
                                                              onSelect(event);
                                                              event.room
                                                                  .sendReaction(
                                                                    event
                                                                        .eventId,
                                                                    emoji,
                                                                  );
                                                            },
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    2,
                                                  ),
                                                  child: IconButton(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: theme
                                                          .colorScheme
                                                          .surfaceContainerHighest,
                                                      minimumSize: const Size(
                                                        38,
                                                        38,
                                                      ),
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .add_reaction_outlined,
                                                      size: 20,
                                                    ),
                                                    tooltip: L10n.of(context)
                                                        .customReaction,
                                                    onPressed: () async {
                                                      final emoji = await showAdaptiveBottomSheet<String>(
                                                        context: context,
                                                        builder: (context) => Scaffold(
                                                          appBar: AppBar(
                                                            title: Text(
                                                              L10n.of(
                                                                context,
                                                              ).customReaction,
                                                            ),
                                                            leading: CloseButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                    context,
                                                                  ).pop(null),
                                                            ),
                                                          ),
                                                          body: SizedBox(
                                                            height:
                                                                double.infinity,
                                                            child: DefaultTabController(
                                                              length: 2,
                                                              child: Column(
                                                                children: [
                                                                  TabBar(
                                                                    tabs: [
                                                                      Tab(
                                                                        text: L10n.of(
                                                                          context,
                                                                        ).emojis,
                                                                      ),
                                                                      Tab(
                                                                        text: L10n.of(
                                                                          context,
                                                                        ).stickers,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  Expanded(
                                                                    child: TabBarView(
                                                                      children: [
                                                                        EmojiPicker(
                                                                          onEmojiSelected: (
                                                                            _,
                                                                            emoji,
                                                                          ) => Navigator.of(context).pop(emoji.emoji),
                                                                          config: Config(
                                                                            locale: Localizations.localeOf(
                                                                              context,
                                                                            ),
                                                                            emojiViewConfig: const EmojiViewConfig(
                                                                              backgroundColor: Colors.transparent,
                                                                            ),
                                                                            bottomActionBarConfig: const BottomActionBarConfig(
                                                                              enabled: false,
                                                                            ),
                                                                            categoryViewConfig: CategoryViewConfig(
                                                                              initCategory: Category.SMILEYS,
                                                                              backspaceColor: theme.colorScheme.primary,
                                                                              iconColor: theme.colorScheme.primary.withAlpha(
                                                                                128,
                                                                              ),
                                                                              iconColorSelected: theme.colorScheme.primary,
                                                                              indicatorColor: theme.colorScheme.primary,
                                                                              backgroundColor: theme.colorScheme.surface,
                                                                            ),
                                                                            skinToneConfig: SkinToneConfig(
                                                                              dialogBackgroundColor: Color.lerp(
                                                                                theme.colorScheme.surface,
                                                                                theme.colorScheme.primaryContainer,
                                                                                0.75,
                                                                              )!,
                                                                              indicatorColor: theme.colorScheme.onSurface,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        StickerPickerDialog(
                                                                          room:
                                                                              event.room,
                                                                          usage:
                                                                              ImagePackUsage.emoticon,
                                                                          onSelected: (sticker) => Navigator.of(
                                                                            context,
                                                                          ).pop(sticker.url.toString()),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                      if (emoji == null) {
                                                        return;
                                                      }
                                                      if (sentReactions
                                                          .contains(emoji)) {
                                                        return;
                                                      }
                                                      onSelect(event);

                                                      await event.room
                                                          .sendReaction(
                                                            event.eventId,
                                                            emoji,
                                                          );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (enterThread != null)
                _MessageThreadPreview(
                  event: event,
                  timeline: timeline,
                  enterThread: enterThread,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageStatusMetadata extends StatefulWidget {
  final Event event;
  final bool ownMessage;
  final bool showTime;
  final bool detailedTime;
  final bool isEdited;
  final Color textColor;
  final Color errorColor;
  final Color? shadowColor;

  const _MessageStatusMetadata({
    required this.event,
    required this.ownMessage,
    required this.showTime,
    required this.detailedTime,
    required this.isEdited,
    required this.textColor,
    required this.errorColor,
    required this.shadowColor,
  });

  @override
  State<_MessageStatusMetadata> createState() => _MessageStatusMetadataState();
}

class _MessageStatusMetadataState extends State<_MessageStatusMetadata> {
  MainAxisAlignment? _alignment;
  String? _timeLabel;
  String? _editedLabel;
  EventStatus? _status;
  String? _statusLabel;
  Color? _textColor;
  Color? _errorColor;
  Color? _shadowColor;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    final status = widget.event.status;
    final alignment = widget.ownMessage
        ? MainAxisAlignment.end
        : MainAxisAlignment.start;
    final l10n = L10n.of(context);
    final timeLabel = status.isSent && widget.showTime
        ? ' ${widget.detailedTime ? widget.event.originServerTs.localizedDetailedTime(context) : widget.event.originServerTs.localizedTimeOfDay(context)}'
        : null;
    final editedLabel = widget.isEdited ? l10n.edited : null;
    final statusLabel = switch (status) {
      EventStatus.error => l10n.couldNotBeSent,
      EventStatus.sending => switch (widget.event.fileSendingStatus) {
        null => l10n.sending,
        FileSendingStatus.generatingThumbnail => l10n.generatingThumbnail,
        FileSendingStatus.encrypting => l10n.encrypting,
        FileSendingStatus.uploading => l10n.uploading,
      },
      _ => null,
    };
    final child = _child;

    if (child != null &&
        alignment == _alignment &&
        timeLabel == _timeLabel &&
        editedLabel == _editedLabel &&
        status == _status &&
        statusLabel == _statusLabel &&
        widget.textColor == _textColor &&
        widget.errorColor == _errorColor &&
        widget.shadowColor == _shadowColor) {
      return child;
    }

    _alignment = alignment;
    _timeLabel = timeLabel;
    _editedLabel = editedLabel;
    _status = status;
    _statusLabel = statusLabel;
    _textColor = widget.textColor;
    _errorColor = widget.errorColor;
    _shadowColor = widget.shadowColor;

    final shadows = widget.shadowColor == null
        ? null
        : [
            Shadow(
              offset: const Offset(0.0, 0.0),
              blurRadius: 2,
              color: widget.shadowColor!,
            ),
          ];

    return _child = Row(
      mainAxisAlignment: alignment,
      children: [
        const SizedBox(width: 8),
        if (timeLabel != null)
          Text(
            timeLabel,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 11,
              shadows: shadows,
            ),
          ),
        if (editedLabel != null) ...[
          const Text(' ', style: TextStyle(fontSize: 11)),
          Text(
            editedLabel,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 11,
              shadows: shadows,
            ),
          ),
        ],
        if (status == EventStatus.error && statusLabel != null) ...[
          const Text(' ', style: TextStyle(fontSize: 11)),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              color: widget.errorColor,
              shadows: shadows,
            ),
          ),
          const Text(' ', style: TextStyle(fontSize: 11)),
          Icon(
            Icons.error_outlined,
            size: 14,
            color: widget.errorColor,
            shadows: shadows,
          ),
        ],
        if (status == EventStatus.sending && statusLabel != null) ...[
          Text(
            statusLabel,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 11,
              shadows: shadows,
            ),
          ),
          const Text(' ', style: TextStyle(fontSize: 11)),
          const SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(strokeWidth: 1),
          ),
        ],
      ],
    );
  }
}

class _MessageThreadPreview extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final void Function(String eventId) enterThread;

  const _MessageThreadPreview({
    required this.event,
    required this.timeline,
    required this.enterThread,
  });

  @override
  State<_MessageThreadPreview> createState() => _MessageThreadPreviewState();
}

class _MessageThreadPreviewState extends State<_MessageThreadPreview> {
  bool? _empty;
  String? _label;
  Color? _foregroundColor;
  Color? _backgroundColor;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    final threadChildren = widget.event.aggregatedEvents(
      widget.timeline,
      RelationshipTypes.thread,
    );
    final child = _child;

    if (threadChildren.isEmpty) {
      if (child != null && _empty == true) {
        return child;
      }
      _empty = true;
      _label = null;
      _foregroundColor = null;
      _backgroundColor = null;
      return _child = AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        alignment: Alignment.bottomCenter,
        child: const SizedBox.shrink(),
      );
    }

    final l10n = L10n.of(context);
    final label =
        '${l10n.countReplies(threadChildren.length)} | '
        '${threadChildren.first.calcLocalizedBodyFallback(MatrixLocals(l10n), withSenderNamePrefix: true)}';
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onSecondaryContainer;
    final backgroundColor = colorScheme.secondaryContainer;

    if (child != null &&
        _empty == false &&
        label == _label &&
        foregroundColor == _foregroundColor &&
        backgroundColor == _backgroundColor) {
      return child;
    }

    _empty = false;
    _label = label;
    _foregroundColor = foregroundColor;
    _backgroundColor = backgroundColor;

    return _child = AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(
          top: 2.0,
          bottom: 8.0,
          left: Avatar.defaultSize + 8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.columnWidth * 1.5,
          ),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              foregroundColor: foregroundColor,
              backgroundColor: backgroundColor,
            ),
            onPressed: () => widget.enterThread(widget.event.eventId),
            icon: const Icon(Icons.message),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

class BubbleBackground extends StatelessWidget {
  const BubbleBackground({
    super.key,
    required this.scrollController,
    required this.colors,
    required this.ignore,
    required this.child,
  });

  final ScrollController scrollController;
  final List<Color> colors;
  final bool ignore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ignore) return child;
    return CustomPaint(
      painter: BubblePainter(
        repaint: scrollController,
        colors: colors,
        context: context,
      ),
      child: child,
    );
  }
}

class BubblePainter extends CustomPainter {
  BubblePainter({
    required this.context,
    required this.colors,
    required super.repaint,
  });

  final BuildContext context;
  final List<Color> colors;
  ScrollableState? _scrollable;

  @override
  void paint(Canvas canvas, Size size) {
    final scrollable = _scrollable ??= Scrollable.of(context);
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox;
    final scrollableRect = Offset.zero & scrollableBox.size;
    final bubbleBox = context.findRenderObject() as RenderBox;

    final origin = bubbleBox.localToGlobal(
      Offset.zero,
      ancestor: scrollableBox,
    );
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        scrollableRect.topCenter,
        scrollableRect.bottomCenter,
        colors,
        [0.0, 1.0],
        TileMode.clamp,
        Matrix4.translationValues(-origin.dx, -origin.dy, 0.0).storage,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(BubblePainter oldDelegate) {
    final scrollable = Scrollable.of(context);
    final oldScrollable = _scrollable;
    _scrollable = scrollable;
    return scrollable.position != oldScrollable?.position;
  }
}

class _AnimateIn extends StatefulWidget {
  final bool animateIn;
  final Widget child;
  const _AnimateIn({required this.animateIn, required this.child, super.key});

  @override
  State<_AnimateIn> createState() => __AnimateInState();
}

class __AnimateInState extends State<_AnimateIn> {
  bool _animationFinished = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animateIn) return widget.child;
    if (!_animationFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _animationFinished = true;
        });
      });
    }

    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: _animationFinished ? widget.child : const SizedBox.shrink(),
    );
  }
}
