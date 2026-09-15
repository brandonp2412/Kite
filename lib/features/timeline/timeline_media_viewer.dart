import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

abstract interface class TimelineMediaActionPort {
  Future<void> save({required String roomId, required TimelineMessage message});

  Future<void> share({
    required String roomId,
    required TimelineMessage message,
  });
}

final class DeterministicTimelineMediaActionPort
    implements TimelineMediaActionPort {
  const DeterministicTimelineMediaActionPort({this.latency = Duration.zero});

  final Duration latency;

  @override
  Future<void> save({
    required String roomId,
    required TimelineMessage message,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<void> share({
    required String roomId,
    required TimelineMessage message,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }
}

abstract interface class TimelineMediaResolver {
  MediaVisualBuilder thumbnailFor(TimelineMessage message);

  Future<MediaVisualBuilder> loadFullResolution(TimelineMessage message);
}

final class DeterministicTimelineMediaResolver
    implements TimelineMediaResolver {
  const DeterministicTimelineMediaResolver();

  @override
  MediaVisualBuilder thumbnailFor(TimelineMessage message) {
    final attachment = message.attachment!;
    return (context) => TimelineMediaVisual(attachment: attachment);
  }

  @override
  Future<MediaVisualBuilder> loadFullResolution(TimelineMessage message) {
    final attachment = message.attachment!;
    return Future<MediaVisualBuilder>.value(
      (context) => TimelineMediaVisual(attachment: attachment, detailed: true),
    );
  }
}

@immutable
final class TimelineMediaViewerModel {
  const TimelineMediaViewerModel({
    required this.items,
    required this.initialIndex,
    required this.onSave,
    required this.onShare,
  });

  factory TimelineMediaViewerModel.fromMessages({
    required String roomId,
    required List<TimelineMessage> messages,
    required String initialMessageId,
    TimelineMediaResolver resolver = const DeterministicTimelineMediaResolver(),
    TimelineMediaActionPort actionPort =
        const DeterministicTimelineMediaActionPort(),
  }) {
    final mediaMessages = messages
        .where(
          (message) =>
              !message.redacted &&
              message.attachment != null &&
              message.attachment!.kind != TimelineAttachmentKind.file,
        )
        .toList(growable: false);
    final initialIndex = mediaMessages.indexWhere(
      (message) => message.id == initialMessageId,
    );
    if (initialIndex < 0) {
      throw ArgumentError.value(
        initialMessageId,
        'initialMessageId',
        'The initial event must be visible media',
      );
    }

    final messageById = <String, TimelineMessage>{
      for (final message in mediaMessages) message.id: message,
    };
    return TimelineMediaViewerModel(
      initialIndex: initialIndex,
      items: List<MediaViewerItem>.unmodifiable(<MediaViewerItem>[
        for (final message in mediaMessages)
          MediaViewerItem(
            id: message.id,
            heroTag: timelineMediaHeroTag(message),
            semanticLabel: timelineMediaSemanticLabel(message),
            thumbnailBuilder: resolver.thumbnailFor(message),
            loadFullResolution: () => resolver.loadFullResolution(message),
            caption: message.body.isEmpty ? null : TextSpan(text: message.body),
          ),
      ]),
      onSave: (item) =>
          actionPort.save(roomId: roomId, message: messageById[item.id]!),
      onShare: (item) =>
          actionPort.share(roomId: roomId, message: messageById[item.id]!),
    );
  }

  final List<MediaViewerItem> items;
  final int initialIndex;
  final MediaViewerActionHandler onSave;
  final MediaViewerActionHandler onShare;
}

Object timelineMediaHeroTag(TimelineMessage message) =>
    'timeline-media-${message.id}-${message.attachment!.id}';

String timelineMediaSemanticLabel(TimelineMessage message) {
  final attachment = message.attachment!;
  final type = switch (attachment.kind) {
    TimelineAttachmentKind.image => 'Image',
    TimelineAttachmentKind.video => 'Video',
    TimelineAttachmentKind.file => 'File',
  };
  return '$type: ${attachment.name}';
}

class TimelineMediaVisual extends StatelessWidget {
  const TimelineMediaVisual({
    super.key,
    required this.attachment,
    this.detailed = false,
  });

  final TimelineAttachment attachment;
  final bool detailed;

  int get _seed => attachment.id.codeUnits.fold<int>(
    attachment.kind.index * 41 + 17,
    (value, unit) => (value * 33 + unit) & 0xFFFFFF,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seed = _seed;
    final tint = Color(0xFF000000 | seed);
    final accent = Color.lerp(colors.primary, tint, 0.34)!;
    final base = Color.lerp(colors.surfaceContainerHighest, tint, 0.14)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[base, accent.withValues(alpha: 0.72)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Icon(
              attachment.kind == TimelineAttachmentKind.video
                  ? Icons.play_circle_fill_rounded
                  : Icons.image_rounded,
              size: detailed ? 88 : 42,
              color: colors.onPrimary.withValues(alpha: detailed ? 0.64 : 0.78),
            ),
          ),
          Positioned(
            left: KiteSpacing.sm,
            right: KiteSpacing.sm,
            bottom: KiteSpacing.xs,
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KiteTypography.metadata.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (detailed)
            Positioned(
              right: KiteSpacing.sm,
              top: KiteSpacing.sm,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(KiteRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.sm,
                    vertical: KiteSpacing.xs,
                  ),
                  child: Text(
                    attachment.sizeLabel,
                    style: KiteTypography.metadata.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
