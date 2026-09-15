import 'package:flutter/material.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';

abstract interface class ThreadMediaActionPort {
  Future<void> save({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  });

  Future<void> share({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  });
}

final class DeterministicThreadMediaActionPort
    implements ThreadMediaActionPort {
  const DeterministicThreadMediaActionPort({this.latency = Duration.zero});

  final Duration latency;

  @override
  Future<void> save({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<void> share({
    required String roomId,
    required String parentEventId,
    required ThreadReply reply,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }
}

abstract interface class ThreadMediaResolver {
  MediaVisualBuilder thumbnailFor(ThreadReply reply);

  Future<MediaVisualBuilder> loadFullResolution(ThreadReply reply);
}

final class DeterministicThreadMediaResolver implements ThreadMediaResolver {
  const DeterministicThreadMediaResolver();

  @override
  MediaVisualBuilder thumbnailFor(ThreadReply reply) {
    final attachment = reply.attachment!;
    return (context) => TimelineMediaVisual(attachment: attachment);
  }

  @override
  Future<MediaVisualBuilder> loadFullResolution(ThreadReply reply) {
    final attachment = reply.attachment!;
    return Future<MediaVisualBuilder>.value(
      (context) => TimelineMediaVisual(attachment: attachment, detailed: true),
    );
  }
}

@immutable
final class ThreadMediaViewerModel {
  const ThreadMediaViewerModel({
    required this.items,
    required this.initialIndex,
    required this.onSave,
    required this.onShare,
  });

  factory ThreadMediaViewerModel.fromReplies({
    required String roomId,
    required TimelineMessage parent,
    required List<ThreadReply> replies,
    required String initialReplyId,
    ThreadMediaResolver resolver = const DeterministicThreadMediaResolver(),
    ThreadMediaActionPort actionPort =
        const DeterministicThreadMediaActionPort(),
  }) {
    final mediaReplies = replies
        .where(
          (reply) =>
              reply.attachment != null && reply.attachment!.kind.isVisualMedia,
        )
        .toList(growable: false);
    final initialIndex = mediaReplies.indexWhere(
      (reply) => reply.id == initialReplyId,
    );
    if (initialIndex < 0) {
      throw ArgumentError.value(
        initialReplyId,
        'initialReplyId',
        'The initial thread reply must contain visible media',
      );
    }

    final replyById = <String, ThreadReply>{
      for (final reply in mediaReplies) reply.id: reply,
    };
    return ThreadMediaViewerModel(
      initialIndex: initialIndex,
      items: List<MediaViewerItem>.unmodifiable(<MediaViewerItem>[
        for (final reply in mediaReplies)
          MediaViewerItem(
            id: reply.id,
            heroTag: threadMediaHeroTag(parent, reply),
            semanticLabel: threadMediaSemanticLabel(reply),
            thumbnailBuilder: resolver.thumbnailFor(reply),
            loadFullResolution: () => resolver.loadFullResolution(reply),
            caption: reply.body.isEmpty ? null : TextSpan(text: reply.body),
          ),
      ]),
      onSave: (item) => actionPort.save(
        roomId: roomId,
        parentEventId: parent.id,
        reply: replyById[item.id]!,
      ),
      onShare: (item) => actionPort.share(
        roomId: roomId,
        parentEventId: parent.id,
        reply: replyById[item.id]!,
      ),
    );
  }

  final List<MediaViewerItem> items;
  final int initialIndex;
  final MediaViewerActionHandler onSave;
  final MediaViewerActionHandler onShare;
}

Object threadMediaHeroTag(TimelineMessage parent, ThreadReply reply) =>
    'thread-media-${parent.id}-${reply.id}-${reply.attachment!.id}';

String threadMediaSemanticLabel(ThreadReply reply) {
  final attachment = reply.attachment!;
  final type = switch (attachment.kind) {
    TimelineAttachmentKind.image => 'Image',
    TimelineAttachmentKind.video => 'Video',
    TimelineAttachmentKind.file => 'File',
    TimelineAttachmentKind.audio => 'Audio',
    TimelineAttachmentKind.voice => 'Voice message',
  };
  return '$type in thread from ${reply.sender}: ${attachment.name}';
}
