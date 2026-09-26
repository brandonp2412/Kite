import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/timeline/timeline_attachment_formatting.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_message_body.dart';
import 'package:video_player/video_player.dart';

abstract interface class TimelineMediaActionPort {
  Future<void> save({required String roomId, required TimelineMessage message});

  Future<void> share({
    required String roomId,
    required TimelineMessage message,
  });
}

abstract interface class TimelineMediaPlaybackPort {
  Future<Uint8List> loadOriginal({
    required String roomId,
    required TimelineMessage message,
  });
}

typedef TimelineMediaPlaybackLoader = Future<Uint8List> Function(
  TimelineMessage message,
);

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

enum TimelineMediaImageVariant { thumbnail, fullResolution }

typedef TimelineMediaImageProvider = ImageProvider<Object>? Function(
  TimelineAttachment attachment,
  TimelineMediaImageVariant variant,
);

abstract interface class TimelineMediaResolver {
  MediaVisualBuilder thumbnailFor(TimelineMessage message);

  Future<MediaVisualBuilder> loadFullResolution(TimelineMessage message);
}

final class DeterministicTimelineMediaResolver
    implements TimelineMediaResolver {
  const DeterministicTimelineMediaResolver({
    this.imageProvider,
    this.playbackLoader,
  });

  final TimelineMediaImageProvider? imageProvider;
  final TimelineMediaPlaybackLoader? playbackLoader;

  @override
  MediaVisualBuilder thumbnailFor(TimelineMessage message) {
    final attachment = message.attachment!;
    return (context) => TimelineMediaVisual(
      attachment: attachment,
      imageProvider: imageProvider?.call(
        attachment,
        TimelineMediaImageVariant.thumbnail,
      ),
    );
  }

  @override
  Future<MediaVisualBuilder> loadFullResolution(TimelineMessage message) async {
    final attachment = message.attachment!;
    final loadPlayback = playbackLoader;
    if (attachment.kind == TimelineAttachmentKind.video &&
        loadPlayback != null) {
      try {
        final bytes = await loadPlayback(message);
        if (bytes.isNotEmpty) {
          return (context) =>
              TimelineVideoPlayer(attachment: attachment, bytes: bytes);
        }
      } catch (_) {
        // Keep the viewer usable when the original video cannot be resolved.
      }
    }
    return (context) => TimelineMediaVisual(
      attachment: attachment,
      imageProvider: imageProvider?.call(
        attachment,
        TimelineMediaImageVariant.fullResolution,
      ),
      detailed: true,
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
    TimelineMediaResolver? resolver,
    TimelineMediaImageProvider? imageProvider,
    TimelineMediaActionPort actionPort =
        const DeterministicTimelineMediaActionPort(),
  }) {
    final mediaMessages = messages
        .where(
          (message) =>
              !message.redacted &&
              message.attachment != null &&
              message.attachment!.kind.isVisualMedia,
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

    final playbackPort = actionPort is TimelineMediaPlaybackPort
        ? actionPort as TimelineMediaPlaybackPort
        : null;
    final resolvedResolver =
        resolver ??
        DeterministicTimelineMediaResolver(
          imageProvider: imageProvider,
          playbackLoader: playbackPort == null
              ? null
              : (message) =>
                    playbackPort.loadOriginal(roomId: roomId, message: message),
        );
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
            thumbnailBuilder: resolvedResolver.thumbnailFor(message),
            loadFullResolution: () =>
                resolvedResolver.loadFullResolution(message),
            caption: message.body.isEmpty || message.formattedBody != null
                ? null
                : TextSpan(text: message.body),
            captionBuilder:
                message.body.isEmpty || message.formattedBody == null
                ? null
                : (context) {
                    final theme = Theme.of(context);
                    final colors = theme.colorScheme;
                    return Theme(
                      data: theme.copyWith(
                        colorScheme: colors.copyWith(
                          onSurface: Colors.white,
                          onSurfaceVariant: Colors.white70,
                          primary: Colors.white,
                          primaryContainer: Colors.white24,
                          surfaceContainerLow: Colors.black54,
                          outlineVariant: Colors.white24,
                        ),
                      ),
                      child: TimelineMessageBody(
                        body: message.body,
                        formattedBody: message.formattedBody,
                        textKey: const Key('media-caption-rich-text'),
                      ),
                    );
                  },
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
    TimelineAttachmentKind.audio => 'Audio',
    TimelineAttachmentKind.voice => 'Voice message',
  };
  return '$type: ${attachment.name}';
}

class TimelineVideoPlayer extends StatefulWidget {
  const TimelineVideoPlayer({
    super.key,
    required this.attachment,
    required this.bytes,
  });

  final TimelineAttachment attachment;
  final Uint8List bytes;

  @override
  State<TimelineVideoPlayer> createState() => _TimelineVideoPlayerState();
}

class _TimelineVideoPlayerState extends State<TimelineVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final mimeType = widget.attachment.mimeType?.trim().isNotEmpty == true
          ? widget.attachment.mimeType!.trim()
          : 'video/mp4';
      final controller = VideoPlayerController.networkUrl(
        Uri.dataFromBytes(widget.bytes, mimeType: mimeType),
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlaybackChanged);
      _controller = controller;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onPlaybackChanged);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return TimelineMediaVisual(attachment: widget.attachment, detailed: true);
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: SizedBox.square(
          key: Key('timeline-video-loading'),
          dimension: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    final value = controller.value;
    final aspectRatio = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio
        : 16 / 9;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          Center(
            child: Semantics(
              button: true,
              label: value.isPlaying ? 'Pause video' : 'Play video',
              child: IconButton.filled(
                key: const Key('timeline-video-play-pause'),
                tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                onPressed: _togglePlayback,
                iconSize: 38,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
          ),
          Positioned(
            left: KiteSpacing.md,
            right: KiteSpacing.md,
            bottom: KiteSpacing.md,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineMediaVisual extends StatelessWidget {
  const TimelineMediaVisual({
    super.key,
    required this.attachment,
    this.imageProvider,
    this.detailed = false,
  });

  final TimelineAttachment attachment;
  final ImageProvider<Object>? imageProvider;
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

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[base, accent.withValues(alpha: 0.72)],
        ),
      ),
      child: Center(
        child: Icon(
          switch (attachment.kind) {
            TimelineAttachmentKind.video => Icons.play_circle_fill_rounded,
            TimelineAttachmentKind.image => Icons.image_rounded,
            TimelineAttachmentKind.file => Icons.insert_drive_file_rounded,
            TimelineAttachmentKind.audio => Icons.graphic_eq_rounded,
            TimelineAttachmentKind.voice => Icons.mic_rounded,
          },
          size: detailed ? 88 : 42,
          color: colors.onPrimary.withValues(alpha: detailed ? 0.64 : 0.78),
        ),
      ),
    );
    final provider = imageProvider;
    final visual =
        (attachment.kind == TimelineAttachmentKind.image ||
                attachment.kind == TimelineAttachmentKind.video) &&
            provider != null
        ? Image(
            image: provider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          )
        : fallback;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        visual,
        if (attachment.kind == TimelineAttachmentKind.video)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(
                dimension: 56,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (detailed)
          Positioned(
            left: KiteSpacing.sm,
            right: KiteSpacing.sm,
            bottom: KiteSpacing.sm,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(KiteRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KiteSpacing.sm,
                  vertical: KiteSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: KiteSpacing.sm),
                    Text(
                      timelineAttachmentSizeLabel(context, attachment),
                      style: KiteTypography.metadata.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
