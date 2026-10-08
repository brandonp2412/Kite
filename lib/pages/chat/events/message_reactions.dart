// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:kite/widgets/avatar.dart';
import 'package:kite/widgets/future_loading_dialog.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:kite/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageReactions extends StatefulWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  @override
  State<MessageReactions> createState() => _MessageReactionsState();
}

class _MessageReactionsState extends State<MessageReactions> {
  Set<Event> _reactionEvents = const <Event>{};
  Event? _event;
  Timeline? _timeline;
  Client? _client;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final timeline = widget.timeline;
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final client = Matrix.of(context).client;

    final child = _child;
    if (child != null &&
        identical(event, _event) &&
        identical(timeline, _timeline) &&
        identical(client, _client) &&
        setEquals(allReactionEvents, _reactionEvents)) {
      return child;
    }

    _event = event;
    _timeline = timeline;
    _client = client;
    _reactionEvents = Set<Event>.of(allReactionEvents);

    final reactionMap = <String, _ReactionEntry>{};

    for (final e in allReactionEvents) {
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactors: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactors!.add(e.senderFromMemoryOrFallback);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return _child = Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      alignment: ownMessage ? WrapAlignment.end : WrapAlignment.start,
      children: [
        ...reactionList.map(
          (r) => _Reaction(
            reactionKey: r.key,
            count: r.count,
            reacted: r.reacted,
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: evt.redactEvent,
                  );
                }
              } else {
                event.room.sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async {
              final currentReactionEvents = event.aggregatedEvents(
                timeline,
                RelationshipTypes.reaction,
              );
              final reactors = currentReactionEvents
                  .where(
                    (e) => e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                  )
                  .map((e) => e.senderFromMemoryOrFallback)
                  .toList();
              await _AdaptableReactorsDialog(
                client: Matrix.of(context).client,
                reactionEntry: _ReactionEntry(
                  key: r.key,
                  count: reactors.length,
                  reacted: currentReactionEvents.any(
                    (e) =>
                        e.senderId == e.room.client.userID &&
                        e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                  ),
                  reactors: reactors,
                ),
              ).show(context);
            },
          ),
        ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool? reacted;
  final void Function()? onTap;
  final void Function()? onLongPress;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = reacted == true;
    final foregroundColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final backgroundColor = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    Widget content;
    if (reactionKey.startsWith('mxc://')) {
      content = MxcImage(
        uri: Uri.parse(reactionKey),
        width: 18,
        height: 18,
        animated: false,
        isThumbnail: false,
      );
    } else {
      var renderKey = Characters(reactionKey);
      if (renderKey.length > 10) {
        renderKey = renderKey.getRange(0, 9) + Characters('…');
      }
      content = Text(
        renderKey.toString(),
        style: const TextStyle(fontSize: 16),
      );
    }

    return Material(
      color: backgroundColor,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary.withAlpha(160)
              : theme.colorScheme.outlineVariant.withAlpha(96),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: count > 1 ? 8 : 7,
            vertical: 3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              if (count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<User>? reactors;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactors,
  });
}

class _AdaptableReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;

  const _AdaptableReactorsDialog({this.client, this.reactionEntry});

  Future<bool?> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => this,
    barrierDismissible: true,
    useRootNavigator: false,
  );

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in reactionEntry!.reactors!)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.displayName,
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(reactor.displayName!),
            ),
        ],
      ),
    );

    final title = Center(child: Text(reactionEntry!.key));

    return AlertDialog(title: title, content: body);
  }
}
