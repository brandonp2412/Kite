import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_attachment_formatting.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:signals/signals_flutter.dart';

enum ComposerAttachmentSource { photos, videos, camera, files }

abstract interface class ComposerAttachmentPicker {
  Set<ComposerAttachmentSource> get supportedSources;

  Future<TimelineAttachment?> pick(ComposerAttachmentSource source);
}

const deterministicComposerAttachments = <TimelineAttachment>[
  TimelineAttachment(
    id: 'photo-library',
    kind: TimelineAttachmentKind.image,
    name: 'IMG_2048.jpg',
    sizeLabel: '2.4 MB · Photo',
  ),
  TimelineAttachment(
    id: 'video-library',
    kind: TimelineAttachmentKind.video,
    name: 'VID_1032.mp4',
    sizeLabel: '18.2 MB · Video',
  ),
  TimelineAttachment(
    id: 'camera-photo',
    kind: TimelineAttachmentKind.image,
    name: 'Camera photo.jpg',
    sizeLabel: '3.1 MB · Camera',
  ),
  TimelineAttachment(
    id: 'document-file',
    kind: TimelineAttachmentKind.file,
    name: 'project-notes.pdf',
    sizeLabel: '840 KB · PDF',
  ),
];

Future<TimelineAttachment?> showComposerAttachmentPicker(
  BuildContext context, {
  ComposerAttachmentPicker? attachmentPicker,
  ValueChanged<TimelineLocationKind>? onLocationSelected,
  bool allowLiveLocation = true,
  VoidCallback? onPollSelected,
}) {
  return showModalBottomSheet<TimelineAttachment>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.kiteColors.canvas,
    constraints: const BoxConstraints(maxWidth: 440),
    builder: (_) => ComposerAttachmentPickerSheet(
      attachmentPicker: attachmentPicker,
      onLocationSelected: onLocationSelected,
      allowLiveLocation: allowLiveLocation,
      onPollSelected: onPollSelected,
    ),
  );
}

class ComposerAttachmentPickerSheet extends StatelessWidget {
  const ComposerAttachmentPickerSheet({
    super.key,
    this.attachmentPicker,
    this.onLocationSelected,
    this.allowLiveLocation = true,
    this.onPollSelected,
  });

  final ComposerAttachmentPicker? attachmentPicker;
  final ValueChanged<TimelineLocationKind>? onLocationSelected;
  final bool allowLiveLocation;
  final VoidCallback? onPollSelected;

  static const _labels = <String>['Photos', 'Videos', 'Camera', 'Files'];
  static const _sources = <ComposerAttachmentSource>[
    ComposerAttachmentSource.photos,
    ComposerAttachmentSource.videos,
    ComposerAttachmentSource.camera,
    ComposerAttachmentSource.files,
  ];

  static const _icons = <IconData>[
    Icons.photo_library_outlined,
    Icons.video_library_outlined,
    Icons.photo_camera_outlined,
    Icons.attach_file_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      for (
        var index = 0;
        index < deterministicComposerAttachments.length;
        index++
      )
        if (attachmentPicker == null ||
            attachmentPicker!.supportedSources.contains(_sources[index]))
          _ComposerAttachmentActionTile(
            key: Key(
              'attachment-option-${deterministicComposerAttachments[index].id}',
            ),
            icon: _icons[index],
            label: _labels[index],
            onTap: () async {
              final picker = attachmentPicker;
              final attachment = picker == null
                  ? deterministicComposerAttachments[index]
                  : await picker.pick(_sources[index]);
              if (context.mounted && attachment != null) {
                Navigator.of(context).pop(attachment);
              }
            },
          ),
      if (onLocationSelected != null)
        _ComposerAttachmentActionTile(
          key: const Key('attachment-option-location'),
          icon: Icons.location_on_outlined,
          label: 'Location',
          onTap: () {
            Navigator.of(context).pop();
            onLocationSelected!(TimelineLocationKind.staticLocation);
          },
        ),
      if (onLocationSelected != null && allowLiveLocation)
        _ComposerAttachmentActionTile(
          key: const Key('attachment-option-live-location'),
          icon: Icons.my_location_rounded,
          label: 'Live location',
          onTap: () {
            Navigator.of(context).pop();
            onLocationSelected!(TimelineLocationKind.liveLocation);
          },
        ),
      if (onPollSelected != null)
        _ComposerAttachmentActionTile(
          key: const Key('attachment-option-poll'),
          icon: Icons.poll_outlined,
          label: 'Poll',
          onTap: () {
            Navigator.of(context).pop();
            onPollSelected!();
          },
        ),
    ];

    return Padding(
      key: const Key('attachment-picker-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        0,
        KiteSpacing.md,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Add attachment',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: KiteSpacing.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: KiteSpacing.sm,
            crossAxisSpacing: KiteSpacing.sm,
            childAspectRatio: 1.2,
            children: actions,
          ),
        ],
      ),
    );
  }
}

class _ComposerAttachmentActionTile extends StatelessWidget {
  const _ComposerAttachmentActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(KiteRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(KiteRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(KiteSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 42,
                    child: Icon(
                      icon,
                      size: 21,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: KiteSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: KiteTypography.metadata.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
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

class ComposerAttachmentPreview extends StatelessWidget {
  const ComposerAttachmentPreview({
    super.key,
    required this.attachment,
    this.onEdit,
    required this.onRemove,
  });

  final TimelineAttachment attachment;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('composer-attachment-preview'),
      height: 68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.md,
          KiteSpacing.xs,
          KiteSpacing.md,
          0,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(KiteRadii.md),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
              width: KiteStroke.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: KiteSpacing.sm),
              SizedBox.square(
                dimension: 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(KiteRadii.sm),
                  ),
                  child: Icon(
                    _attachmentIcon(attachment.kind),
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: KiteSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.name,
                      key: const Key('composer-attachment-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      timelineAttachmentSizeLabel(context, attachment),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  key: const Key('composer-attachment-edit'),
                  tooltip: 'Crop or rotate image',
                  onPressed: onEdit,
                  icon: const Icon(Icons.crop_rotate_rounded, size: 19),
                ),
              IconButton(
                key: const Key('composer-attachment-remove'),
                tooltip: 'Remove attachment',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
              const SizedBox(width: KiteSpacing.xxs),
            ],
          ),
        ),
      ),
    );
  }
}

class ComposerVoiceRecordingIndicator extends StatelessWidget {
  const ComposerVoiceRecordingIndicator({
    super.key,
    required this.elapsed,
    required this.levels,
  });

  final Duration elapsed;
  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleLevels = levels.isEmpty ? const <double>[0.08] : levels;
    return Semantics(
      label: 'Recording voice message, ${_voiceDurationLabel(elapsed)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(KiteRadii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.mic_rounded, size: 19, color: colors.error),
              const SizedBox(width: KiteSpacing.sm),
              Text(
                _voiceDurationLabel(elapsed),
                key: const Key('composer-voice-recording-duration'),
                style: KiteTypography.metadata.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: KiteSpacing.sm),
              Expanded(
                child: Row(
                  key: const Key('composer-voice-recording-waveform'),
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    for (final level
                        in visibleLevels.reversed.take(18).toList().reversed)
                      Container(
                        width: 2,
                        height: 5 + (level.clamp(0.0, 1.0) * 22),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComposerVoiceMessagePreview extends StatelessWidget {
  const ComposerVoiceMessagePreview({
    super.key,
    required this.attachment,
    required this.playing,
    required this.position,
    required this.onToggle,
    required this.onSeek,
    required this.onRemove,
  });

  final TimelineAttachment attachment;
  final bool playing;
  final Duration position;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = attachment.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, durationMs);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(KiteRadii.lg),
      ),
      child: Row(
        children: <Widget>[
          IconButton.filledTonal(
            key: const Key('composer-voice-preview-toggle'),
            tooltip: playing ? 'Pause voice message' : 'Play voice message',
            onPressed: onToggle,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          Expanded(
            child: Slider(
              key: const Key('composer-voice-preview-seek'),
              value: durationMs == 0 ? 0 : positionMs.toDouble(),
              max: durationMs <= 0 ? 1 : durationMs.toDouble(),
              onChanged: durationMs <= 0
                  ? null
                  : (value) => onSeek(Duration(milliseconds: value.round())),
            ),
          ),
          Text(
            _voiceDurationLabel(position > Duration.zero ? position : duration),
            key: const Key('composer-voice-preview-duration'),
            style: KiteTypography.metadata,
          ),
          IconButton(
            key: const Key('composer-voice-preview-remove'),
            tooltip: 'Discard voice message',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

String _voiceDurationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class TimelineAttachmentCard extends StatelessWidget {
  const TimelineAttachmentCard({
    super.key,
    required this.messageId,
    required this.attachment,
    this.audioPlaybackState,
    this.imageProvider,
    this.heroTag,
    this.onTap,
    this.onToggleAudio,
  });

  final String messageId;
  final TimelineAttachment attachment;
  final ReadonlySignal<TimelineAudioPlaybackState>? audioPlaybackState;
  final ImageProvider<Object>? imageProvider;
  final Object? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onToggleAudio;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visualMedia = attachment.kind.isVisualMedia;
    final audio = attachment.kind.isAudio;
    final borderRadius = BorderRadius.circular(KiteRadii.md);
    final visualWidth = (MediaQuery.sizeOf(context).width * 0.72).clamp(
      240.0,
      360.0,
    );
    final media = TimelineMediaVisual(
      attachment: attachment,
      imageProvider: imageProvider,
    );
    final content = visualMedia
        ? heroTag == null
              ? media
              : Hero(tag: heroTag!, child: media)
        : audio
        ? _TimelineAudioCard(
            messageId: messageId,
            attachment: attachment,
            playbackState: audioPlaybackState,
            onToggle: onToggleAudio,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(Icons.insert_drive_file_outlined, color: colors.primary),
                const SizedBox(width: KiteSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        timelineAttachmentSizeLabel(context, attachment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    return Semantics(
      button: visualMedia ? onTap != null : audio && onToggleAudio != null,
      label: visualMedia
          ? '${attachment.name}, open media'
          : audio
          ? '${attachment.kind == TimelineAttachmentKind.voice ? 'Voice message' : 'Audio'}, ${timelineAttachmentDurationLabel(context, attachment)}'
          : attachment.name,
      child: SizedBox(
        key: Key('message-attachment-$messageId'),
        width: visualMedia
            ? visualWidth
            : audio
            ? 250
            : 230,
        height: visualMedia
            ? visualWidth * 0.68
            : audio
            ? 76
            : 58,
        child: Material(
          color: colors.surface.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: visualMedia
                ? BorderSide.none
                : BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.7),
                    width: KiteStroke.hairline,
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: !visualMedia || onTap == null
              ? content
              : InkWell(
                  key: Key('message-attachment-open-$messageId'),
                  onTap: onTap,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _TimelineAudioCard extends StatelessWidget {
  const _TimelineAudioCard({
    required this.messageId,
    required this.attachment,
    required this.playbackState,
    required this.onToggle,
  });

  final String messageId;
  final TimelineAttachment attachment;
  final ReadonlySignal<TimelineAudioPlaybackState>? playbackState;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final voice = attachment.kind == TimelineAttachmentKind.voice;
    final waveform = attachment.waveform.isNotEmpty
        ? attachment.waveform
              .take(19)
              .map((sample) => 7 + sample.clamp(0.0, 1.0) * 16)
              .toList(growable: false)
        : List<double>.generate(
            19,
            (index) =>
                7 +
                ((attachment.id.codeUnitAt(index % attachment.id.length) +
                        index * 5) %
                    16),
            growable: false,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KiteSpacing.sm,
        vertical: KiteSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          SignalBuilder(
            builder: (context) {
              final playing =
                  playbackState?.value == TimelineAudioPlaybackState.playing;
              return IconButton.filledTonal(
                key: Key('audio-toggle-$messageId'),
                tooltip: playing ? 'Pause audio' : 'Play audio',
                onPressed: onToggle,
                style: IconButton.styleFrom(minimumSize: const Size.square(44)),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 24,
                ),
              );
            },
          ),
          const SizedBox(width: KiteSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      voice ? Icons.mic_none_rounded : Icons.graphic_eq_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: KiteSpacing.xxs),
                    Expanded(
                      child: Text(
                        voice ? 'Voice message' : attachment.name,
                        key: Key('audio-title-$messageId'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      timelineAttachmentDurationLabel(context, attachment),
                      key: Key('audio-duration-$messageId'),
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KiteSpacing.xs),
                SizedBox(
                  key: Key('audio-waveform-$messageId'),
                  height: 24,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      for (
                        var index = 0;
                        index < waveform.length;
                        index++
                      ) ...<Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: Container(
                              height: waveform[index],
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(
                                  alpha: index < 6 ? 0.9 : 0.35,
                                ),
                                borderRadius: BorderRadius.circular(
                                  KiteRadii.pill,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (index != waveform.length - 1)
                          const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _attachmentIcon(TimelineAttachmentKind kind) => switch (kind) {
  TimelineAttachmentKind.image => Icons.image_outlined,
  TimelineAttachmentKind.video => Icons.play_circle_outline_rounded,
  TimelineAttachmentKind.file => Icons.insert_drive_file_outlined,
  TimelineAttachmentKind.audio => Icons.graphic_eq_rounded,
  TimelineAttachmentKind.voice => Icons.mic_none_rounded,
};
